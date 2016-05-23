IF EXISTS
    (SELECT *
     FROM sys.objects
     WHERE object_id = OBJECT_ID(N'SPSyncTaskPurchases')
         AND OBJECTPROPERTY(OBJECT_ID(N'SPSyncTaskPurchases'), N'IsProcedure') = 1)

    DROP PROCEDURE SPSyncTaskPurchases

GO

CREATE PROCEDURE SPSyncTaskPurchases
AS
    DECLARE @Retries int
    SET @Retries = 1

    RETRY:
    BEGIN TRY
        BEGIN TRANSACTION

        INSERT INTO B1BBIL.dbo.DocumentLine (cnyId , wheId , docKind , docNum , LineNum , invPartNum , invPartDesc , itmQty , itmPrice , itmERPRefId , itmERPRefNum , itmTax)
        SELECT T1.cnyId ,
               T1.wheId ,
               T1.docKind ,
               T1.docNum ,
               T2.itmERPRefId ,
               T2.invPartNum ,
               T2.invPartDesc ,
               T2.itmQty ,
               D1.itmPrice ,
               0 ,
               T2.itmERPRefNum ,
               ISNULL(D1.itmQty1, 0.00) AS itmTax
        FROM BBIL.dbo.BILDocuments T1 --// docOrigin B

        INNER JOIN BBIL.dbo.BILDocumentItems T2 ON T2.docId = T1.docId -- docRelatedTo del docOrigin = C

        LEFT JOIN
            (SELECT DISTINCT docId ,
                             invPartNum ,
                             itmERPRefId,
                             itmPrice ,
                             itmQty1
             FROM BBIL.dbo.BILDocumentItems
             WHERE docKind = 'PO') D1 ON D1.docId = T1.docRelatedTo
        AND D1.invPartNum = T2.invPartNum
        AND D1.itmERPRefId = T2.itmERPRefId
        WHERE T1.docKind = 'PO'
            AND T1.docStatus = 'CLOSED'
            AND T1.docNum NOT IN
                (SELECT docNum
                 FROM B1BBIL.dbo.Document
                 WHERE docKind = 'PO'
                     AND wheId = T1.wheId)
            INSERT INTO B1BBIL.dbo.Document (cnyId , wheId , docKind , docNum , docDate , cstCode , supCode , docNotes , docTotal , docERPrefId , docERPRefNum , Status)
            SELECT T1.cnyId ,
                   T1.wheId ,
                   T1.docKind ,
                   T1.docNum ,
                   T1.docDate ,
                   T1.cstCode ,
                   T1.supCode ,
                   T1.docNotes ,
                   T1.docTotal ,
                   T1.docERPrefId ,
                   T1.docERPRefNum ,
                   99
            FROM BBIL.dbo.BILDocuments T1 WHERE T1.docOrigin = 'B'
            AND T1.docKind = 'PO'
            AND T1.docStatus = 'CLOSED'
            AND T1.docNum NOT IN
                (SELECT docNum
                 FROM B1BBIL.dbo.Document
                 WHERE docKind = 'PO'
                     AND wheId = T1.wheId --// Bodega A
        )

        UPDATE B1BBIL.dbo.Document
        SET Status = 0
        WHERE docKind = 'PO'
            AND Status = 99

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION

        DECLARE @Retry bit
        DECLARE @ErrorMessage varchar(500)

        SET @Retry = 0

        -- Deadlock?
        IF ERROR_NUMBER() = 1205
        BEGIN
            SET @Retry = 1
            SET @ErrorMessage = ERROR_MESSAGE()
        END

        IF @Retry = 1
        BEGIN
            SET @Retries = @Retries + 1

            /**
             * Retorna control a la rutina principal.
             * Despues de varios intentos, se reporta un evento al Event Log.
             */
            IF (@Retries > 3) RAISERROR(@ErrorMessage, 18, 1)
            ELSE
            BEGIN
                WAITFOR DELAY '00:00:05' -- 5seg
                GOTO RETRY -- re-intentar
            END
        END

    END CATCH
