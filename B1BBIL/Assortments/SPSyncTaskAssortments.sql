IF EXISTS
    (SELECT *
     FROM sys.objects
     WHERE object_id = OBJECT_ID(N'SPSyncTaskAssortments')
         AND OBJECTPROPERTY(OBJECT_ID(N'SPSyncTaskAssortments'), N'IsProcedure') = 1)

    DROP PROCEDURE SPSyncTaskAssortments

GO

CREATE PROCEDURE SPSyncTaskAssortments
AS
    DECLARE @Retries int
    SET @Retries = 1

    DECLARE @MinDocs int,
            @DocId int,
            @DocRelatedTo int,
            @IsMultiLine int,
            @Command nvarchar(max)

    RETRY:
    BEGIN TRY

        /*Buscar el primero bilRowId segun el filtro en orden ascendente*/
        SET @MinDocs =
            (SELECT MIN (T1.bilRowId) 'bilRowId'
             FROM BBIL.dbo.BILDocuments T1
             LEFT JOIN BBIL.dbo.BILDocuments T2 ON T2.docId = T1.docRelatedTo
             WHERE T1.docKind = 'SO'
                 AND T1.docStatus = 'CLOSED'
                 AND T1.docOrigin = 'B'
                 AND T1.cstCode = 'CWW'
                 AND T2.supCode IS NOT NULL
                 AND RTRIM(T1.docNum) NOT IN
                     (SELECT docNum
                      FROM B1BBIL.dbo.Document
                      WHERE docKind = 'SO'
                          AND cstCode = T1.cstCode
                          AND supCode IS NOT NULL
                          AND docNum = T1.docNum
                          AND wheId = T1.wheId))

        WHILE @MinDocs IS NOT NULL
        BEGIN

            /*Buscar docNum y docRelatedTo*/
            SELECT @DocId = docId ,
                   @DocRelatedTo = docRelatedTo
            FROM BBIL.dbo.BILDocuments
            WHERE bilRowId = @MinDocs

            /*Revisar si docNum en detalles tiene mas de 1 lineNum*/
            IF EXISTS
                (SELECT itmERPRefId
                 FROM BBIL.dbo.BILDocumentItems
                 WHERE docId = @DocId
                 GROUP BY itmERPRefId HAVING COUNT (itmErpRefId) > 1) /*Si {n} > 1 entonces, @IsMultiLine = 1. Quiere decir que si hay lineas*/
            SET @IsMultiLine = 1 ELSE /*De lo contrario, {n} < 1, @IsMultiLine = 0. Quiere decir que no es repetido*/
            SET @IsMultiLine = 0

            SET @Command = N'
            INSERT INTO B1BBIL.dbo.DocumentLine (cnyId ,wheId ,docKind ,docNum ,LineNum ,invPartNum ,invPartDesc ,itmQty ,itmTax ,itmPrice ,itmERPRefId ,itmERPRefNum)
            SELECT T2.cnyId ,
                   T2.wheId ,
                   T2.docKind ,
                   T2.docNum ,
                   T2.itmERPRefId ,
                   T2.invPartNum ,
                   T2.invPartDesc ' IF (@IsMultiLine = 1) BEGIN
            SET @Command += N', sum(T2.itmQty) ,
                                sum(isnull(T3.itmQty1, 0.00)) ' END ELSE BEGIN
            SET @Command += N', T2.itmQty ,
                                isnull(T3.itmQty1, 0.00) ' END
            /**
             * T2 alias a el documento de origen BarcodeBox
             * T3 alias a el documento de origen Sap
             *
             * La idea del alias T3 es para leer el impuesto enviado desde Sap ya que BarcodeBox,
             * no incluye impuesto al cerrar el documento.
             */
            SET @Command += N', T2.itmPrice ,
                                0 ,
                                T2.itmERPRefNum
            FROM BBIL.dbo.BILDocumentItems T2
            LEFT JOIN BBIL.dbo.BILDocumentItems T3 ON T3.invPartNum = T2.invPartNum
            AND T3.itmERPRefId = T2.itmERPRefId
            AND T3.docId = ' + CAST(@DocRelatedTo AS varchar(15)) + '
            WHERE T2.docKind = ''SO''
                AND T2.docId = ' + CAST(@DocId AS varchar(15))


            SET @Command += N'
            GROUP BY T2.itmERPRefId ,
                     T2.cnyId ,
                     T2.wheId ,
                     T2.docKind ,
                     T2.docNum ,
                     T2.invPartNum ,
                     T2.invPartDesc ' IF (@IsMultiLine = 0) BEGIN
            SET @Command += N', T2.itmQty ,
                                T3.itmQty1 ' END
            SET @Command += N', T2.itmPrice ,
                                T2.itmERPRefNum
            ORDER BY T2.itmERPRefId '


            SET @Command += N'
            INSERT INTO B1BBIL.dbo.Document
            SELECT T1.cnyId ,
                   T1.wheId ,
                   T1.docKind ,
                   T1.docNum ,
                   T1.docDate ,
                   T1.cstCode ,
                   T2.supCode ,
                   T1.docNotes ,
                   T1.docTotal ,
                   T1.docERPrefId ,
                   T1.docERPRefNum ,
                   99 ,
                   NULL
            FROM BBIL.dbo.BILDocuments T1
            INNER JOIN BBIL.dbo.BILDocuments T2 ON T2.docId = ' + CAST(@DocRelatedTo AS varchar(15)) +
            '
            WHERE T1.docKind = ''SO''
                AND T1.docOrigin = ''B''
                AND T1.docStatus = ''CLOSED''
                AND T1.docId = ' + CAST(@DocId AS varchar(15))


            BEGIN TRANSACTION

            EXECUTE sp_sqlexec @Command

            UPDATE B1BBIL.dbo.Document
            SET Status = 0
            WHERE docKind = 'SO'
                AND Status = 99

            COMMIT TRANSACTION

            --// Reiniciar el contador con el siguiente documento
            SET @MinDocs =
                (SELECT MIN (T1.bilRowId) 'bilRowId'
                 FROM BBIL.dbo.BILDocuments T1
                 INNER JOIN BBIL.dbo.BILDocuments T2 ON T2.docId = T1.docRelatedTo
                 WHERE T1.docKind = 'SO'
                     AND T1.docStatus = 'CLOSED'
                     AND T1.docOrigin = 'B'
                     AND T1.cstCode = 'CWW'
                     AND T2.supCode IS NOT NULL
                     AND rtrim(T1.docNum) NOT IN
                         (SELECT docNum
                          FROM B1BBIL.dbo.Document
                          WHERE docKind = 'SO'
                              AND cstCode = T1.cstCode
                              AND supCode IS NOT NULL
                              AND docNum = T1.docNum
                              AND wheId = T1.wheId)) END
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
