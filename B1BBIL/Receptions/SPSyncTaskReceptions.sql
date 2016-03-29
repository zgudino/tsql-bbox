IF EXISTS
    (SELECT *
     FROM sys.objects
     WHERE object_id = OBJECT_ID(N'SPSyncTaskReceptions')
         AND OBJECTPROPERTY(OBJECT_ID(N'SPSyncTaskReceptions'), N'IsProcedure') = 1)

    DROP PROCEDURE SPSyncTaskReceptions

GO

CREATE PROCEDURE SPSyncTaskReceptions
AS

    DECLARE @Retries int
    SET @Retries = 1

    RETRY:
    BEGIN TRY
        BEGIN TRANSACTION


        INSERT INTO B1BBIL.dbo.DocumentLine (cnyId, wheId, docKind, docNum, LineNum, invPartNum, invPartDesc, itmQty, itmPrice, itmERPRefId, itmERPRefNum)
        SELECT T1.cnyId,
               T1.wheId,
               T1.docKind,
               T1.docNum,
               T1.itmERPRefId,
               T1.invPartNum,
               T1.invPartDesc,
               T1.itmQty,
               T1.itmPrice,
               0,
               T1.itmERPRefNum
        FROM BBIL.dbo.BILDocumentItems T1
        WHERE T1.docKind IN ('RE')
            AND T1.docNum NOT IN
                (SELECT docNum
                 FROM B1BBIL.dbo.DocumentLine
                 WHERE docKind = 'RE')
            AND T1.docNum IN
                (SELECT docNum
                 FROM BBIL.dbo.BILDocuments
                 WHERE docOrigin = 'B'
                     AND docStatus = 'CLOSED'
                     AND docKind IN ('RE'))


        INSERT INTO B1BBIL.dbo.Document (cnyId, wheId, docKind, docNum, docDate, cstCode, supCode, docNotes, docTotal, docERPrefId, docERPRefNum, Status)
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
        FROM BBIL.dbo.BILDocuments T1
        WHERE T1.docOrigin = 'B'
            AND T1.docStatus = 'CLOSED'
            AND T1.docKind IN ('RE')
            AND T1.docNum NOT IN
                (SELECT docNum
                 FROM B1BBIL.dbo.Document
                 WHERE docKind IN ('RE')
                     AND wheId = T1.wheId)

        UPDATE B1BBIL.dbo.Document
        SET Status = 0
        WHERE docKind = 'RE'
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
