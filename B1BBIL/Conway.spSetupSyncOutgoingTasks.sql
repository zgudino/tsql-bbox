USE [B1BBIL]
GO

/****** Object:  StoredProcedure [dbo].[Conway.spSetupSyncOutgoingTasks]    Script Date: 03/28/2016 09:32:15 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE PROC [dbo].[Conway.spSetupSyncOutgoingTasks]
AS

SET XACT_ABORT ON
SET NOCOUNT ON

BEGIN TRY
    BEGIN TRAN INSERT_TRANS_IN_BBIL;
    /*
        ORDENES DE COMPRA

        SISTEMAS
        ©2014 TARGET S.A

        @date: 18.03.2014
        @description: Script toma los documentos cerrados por Barcode Box
        @note: Basado en codigo de Eduardo Olivaren

        @history:
            31.08.2015 - Zahir Gudiño
                + Mejoras drasticas a la consulta de coleccion de detalles para eliminar "redundant lookup"
                    en las columnas itmPrice & itmTax.

                    Mas detalle ver https://vimeo.com/137871733

            28.07.2015 - Zahir Gudiño
                + Refactorizacion de sentencias, minusculas a mayusculas.
                + Identificador "@" en comentarios.
                + Formato de fecha en @history de "/" a ".".
                + Manejo en el caso de Deadlock re-intentar 3 veces.

            28.01.2015 - Zahir Gudiño
                + Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
                + Filtro wheId para evitar conflicto con otros docNum.

            03.05.2014 - Zahir Gudiño
                + Fix left join evitar que se dupliquen lineas al unir documentos
                    con origen B al origen C.

            21.03.2014 - Zahir Gudiño
                + Se agrega isnull(_exp, 0) en el campo itmTax para aliviar caso donde el add-on
                    no inserta datos al ERP por el campo ser nulo.
        */
    DECLARE @retryCounter int
    SET @retryCounter = 1

    RETRY:
    BEGIN TRY
        BEGIN TRANSACTION
        INSERT INTO B1BBIL.dbo.DocumentLine (
            cnyId
            , wheId
            , docKind
            , docNum
            , LineNum
            , invPartNum
            , invPartDesc
            , itmQty
            , itmPrice
            , itmERPRefId
            , itmERPRefNum
            , itmTax
        )

        SELECT T1.cnyId
            , T1.wheId
            , T1.docKind
            , T1.docNum
            , T2.itmERPRefId
            , T2.invPartNum
            , T2.invPartDesc
            , T2.itmQty
            , D1.itmPrice
            , 0
            , T2.itmERPRefNum
            , ISNULL(D1.itmQty1, 0.00) AS itmTax
        FROM BBIL.dbo.BILDocuments T1 --// docOrigin B
            INNER JOIN BBIL.dbo.BILDocumentItems T2 ON T2.docId = T1.docId -- docRelatedTo del docOrigin = C
            LEFT JOIN (
                SELECT DISTINCT docId
                    , invPartNum
                    , itmPrice
                    , itmQty1
                FROM BBIL.dbo.BILDocumentItems
                    WHERE docKind = 'PO'
            ) D1 ON D1.docId = T1.docRelatedTo
                AND D1.invPartNum = T2.invPartNum
        WHERE T1.docKind = 'PO'
                AND T1.docStatus = 'CLOSED'
                AND T1.docNum NOT IN (
                    SELECT docNum
                    FROM B1BBIL.dbo.Document
                    WHERE docKind = 'PO'
                        AND wheId = T1.wheId
                )

        INSERT INTO B1BBIL.dbo.Document (
            cnyId
            , wheId
            , docKind
            , docNum
            , docDate
            , cstCode
            , supCode
            , docNotes
            , docTotal
            , docERPrefId
            , docERPRefNum
            , Status
        )

        SELECT
            T1.cnyId
            , T1.wheId
            , T1.docKind
            , T1.docNum
            , T1.docDate
            , T1.cstCode
            , T1.supCode
            , T1.docNotes
            , T1.docTotal
            , T1.docERPrefId
            , T1.docERPRefNum
            , 99
        FROM BBIL.dbo.BILDocuments T1
        WHERE T1.docOrigin = 'B'
            AND T1.docKind = 'PO'
            AND T1.docStatus = 'CLOSED'
            AND T1.docNum NOT IN (
                SELECT docNum
                FROM B1BBIL.dbo.Document
                WHERE docKind = 'PO'
                    AND wheId = T1.wheId --// Bodega A
            )

        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION
        DECLARE @doRetry bit
        DECLARE @errorMessage varchar(500)

        SET @doRetry = 0

        -- Deadlock?
        IF ERROR_NUMBER() = 1205
        BEGIN
            SET @doRetry = 1
            SET @errorMessage = ERROR_MESSAGE()
        END

        IF @doRetry = 1
        BEGIN
            SET @retryCounter = @retryCounter + 1

            /**
                Retorna control a la rutina principal
                Evento reportado EventLog
                */
            IF (@retryCounter > 3)
            BEGIN
                RAISERROR(@errorMessage,
                    18,
                    1)
            END
            ELSE
            BEGIN
                WAITFOR DELAY '00:00:05' -- 5 sec
                GOTO RETRY -- Reintentar
            END
        END

    END CATCH

        /*
            DESPACHOS MANUALES

            TDS
            © 2014 TARGET S.A

            Autor: Eduardo Olivaren
            Modificado: Zahir Gudino

            Descripcion:
                Agregar tareas de despacho manuales a la cola de salida.

                Aplica a todos aquellos despachos manuales siempre y cuando no sea
                entre bodegas.

            Change Log:
                28/01/2015 - Zahir Gudino
                    + Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
                    + Filtro wheId para evitar conflicto con otros docNum.

        */

        INSERT INTO B1BBIL.dbo.DocumentLine (
            cnyId,
            wheId,
            docKind,
            docNum,
            LineNum,
            invPartNum,
            invPartDesc,
            itmQty,
            itmPrice,
            itmERPRefId,
            itmERPRefNum
        )

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
        WHERE T1.docKind IN ('DE')
            AND T1.docNum NOT IN (
                SELECT docNum
                FROM B1BBIL.dbo.DocumentLine
                WHERE docKind = 'DE'
                    AND wheId = T1.wheId --// Bodega A
            )
            AND T1.docNum IN (
                SELECT docNum
                FROM BBIL.dbo.BILDocuments
                WHERE docOrigin = 'B'
                    AND docStatus = 'CLOSED'
                    AND docKind in ('DE')
            )

        INSERT INTO B1BBIL.dbo.Document (
            cnyId,
            wheId,
            docKind,
            docNum,
            docDate,
            cstCode,
            supCode,
            docNotes,
            docTotal,
            docERPrefId,
            docERPRefNum,
            Status
        )

        SELECT T1.cnyId
            , T1.wheId
            , T1.docKind
            , T1.docNum
            , T1.docDate
            , T1.cstCode
            , T1.supCode
            , T1.docNotes
            , T1.docTotal
            , T1.docERPrefId
            , T1.docERPRefNum
            , 99
        FROM BBIL.dbo.BILDocuments T1
        WHERE T1.docOrigin = 'B'
        AND T1.docStatus = 'CLOSED'
        AND T1.docKind IN ('DE')
        AND T1.docNum NOT IN (
            SELECT docNum
            FROM B1BBIL.dbo.Document
            WHERE docKind IN ('DE')
                AND wheId = T1.wheId -- Bodega A
        )

    /*
            RECIBOS MANUALES

            TDS
            © 2014 TARGET S.A

            Autor: Eduardo Olivaren
            Modificado: Zahir Gudino

            Descripcion:
                Agregar tareas de despacho manuales a la cola de salida.

                Aplica a todos aquellos Recepciones manuales siempre y cuando no sea
                entre bodegas.

            Change Log:
                28/01/2015 - Zahir Gudino
                    + Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
                    + Filtro wheId para evitar conflicto con otros docNum.

    */

    INSERT INTO B1BBIL.dbo.DocumentLine (
        cnyId,
        wheId,
        docKind,
        docNum,
        LineNum,
        invPartNum,
        invPartDesc,
        itmQty,
        itmPrice,
        itmERPRefId,
        itmERPRefNum
    )

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
        AND T1.docNum NOT IN (
                SELECT docNum
          FROM B1BBIL.dbo.DocumentLine
          WHERE docKind = 'RE'
        )
      AND T1.docNum IN (
                SELECT docNum
                FROM BBIL.dbo.BILDocuments
                WHERE docOrigin = 'B'
                                AND docStatus = 'CLOSED'
                                AND docKind in ('RE')
      )

    INSERT INTO B1BBIL.dbo.Document (
        cnyId,
        wheId,
        docKind,
        docNum,
        docDate,
        cstCode,
        supCode,
        docNotes,
        docTotal,
        docERPrefId,
        docERPRefNum,
        Status
    )

    SELECT T1.cnyId
        , T1.wheId
        , T1.docKind
        , T1.docNum
        , T1.docDate
        , T1.cstCode
        , T1.supCode
        , T1.docNotes
        , T1.docTotal
        , T1.docERPrefId
        , T1.docERPRefNum
        , 99
    FROM BBIL.dbo.BILDocuments T1
    WHERE T1.docOrigin = 'B'
    AND T1.docStatus = 'CLOSED'
    AND T1.docKind IN ('RE')
    AND T1.docNum NOT IN (
            SELECT docNum
      FROM B1BBIL.dbo.Document
      WHERE docKind IN ('RE')
                AND wheId = T1.wheId
    )

        /*
            PEDIDOS ENTRE TIENDAS

            Desarrollado por Tecnologia y Desarrollo
            © 2014/TARGET S.A.

            Creado: 13/02/2014

            Descripcion
                El codigo funciona para que capture todo los documentos de venta, pedidos, cerrados por Barcode Box.

            Change Logs
            10/03/2014 - Zahir Gudiño
                + sum(itmQty) soluciona numero de linea (LineNum) repetidos y cosolida en una sola linea.

            18/03/2014
                + Remover rtrim(docId) ya que no es necesario para campos int.
                + Cambio de single comment a block comment en el bloque informativo del codigo.

            21/03/2014 - Zahir Gudino
                + Se incluye impuestos en forma de isnull(sum(_exp, 0.00))

            03/04/2014 - Zahir Gudino
                + Mejora en el script radicalmente. Se consolidaron 2 casos:
                    a. Donde el documento cerrado por Barcode hay LineNum repetidos se consolidan las lineas repetidas
                            se suman itmQty y itmQty1.

                    b. Donde el documento cerrado por Barcode no aya LineNum repetidos se respete cada linea con su valor asignado.

            13/08/2014 -  Zahir Gudiño
                + Reforzamos la relacion entre alias (documento maestro) y tabla actual (documento manual) para que
                    sum(T2.itmQty) no sume la cantidad de articulos en alias.

                    @@add
                        and T3.itmERPRefId = T2.itmERPRefId

            28/01/2015 - Zahir Gudino
                + Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
                + Filtro wheId para evitar conflicto con otros docNum.

            Basado en codigo de Eduardo Olivaren
        */

        DECLARE @min_saledocs int,
            @cur_docid int,
            @cur_docrel int,
            @multi_line int,
            @sales_cmd nvarchar(max)

        --// Buscar el primero bilRowId segun el filtro en orden ascendente
        SET @min_saledocs =
        (
            SELECT MIN(T1.bilRowId) 'bilRowId'
            FROM BBIL.dbo.BILDocuments T1
                LEFT JOIN BBIL.dbo.BILDocuments T2 ON T2.docId = T1.docRelatedTo
            WHERE T1.docKind = 'SO'
                AND T1.docStatus = 'CLOSED'
                AND T1.docOrigin = 'B'
                AND T1.cstCode != 'CWW'
                AND T2.supCode IS NULL
                AND RTRIM(T1.docNum) NOT IN
                (
                    SELECT docNum
                    FROM B1BBIL.dbo.Document
                    WHERE docKind = 'SO'
                        AND cstCode = T1.cstCode
                        AND supCode IS NULL
                        AND wheId = T1.wheId
                        --// Mejora seek time
                        AND docNum = T1.docNum
                )
        )

    WHILE @min_saledocs IS NOT NULL
    BEGIN

      --// Buscar docNum y docRelatedTo
      SELECT @cur_docid = docId
        , @cur_docrel = docRelatedTo
      FROM BBIL.dbo.BILDocuments
      WHERE bilRowId = @min_saledocs

      --// Revisar si docNum en detalles tiene mas de 1 lineNum
      IF EXISTS (
        SELECT itmERPRefId
        FROM BBIL.dbo.BILDocumentItems
        WHERE docId = @cur_docid
        GROUP BY itmERPRefId
        HAVING count(itmErpRefId) > 1
      )
      BEGIN
        -- @multi_line = 1 si {n} > 1
        -- quiere decir que si hay lineas
        SET @multi_line = 1
      END
      ELSE
      BEGIN
        -- de lo contrario {n} < 1
        -- quiere decir que lineNum no esta repetido
        SET @multi_line = 0
      END

      SET @sales_cmd =
      N'
      insert into B1BBIL.dbo.DocumentLine
       (cnyId
       ,wheId
       ,docKind
       ,docNum
       ,LineNum
       ,invPartNum
       ,invPartDesc
       ,itmQty
       ,itmTax
       ,itmPrice
       ,itmERPRefId
       ,itmERPRefNum)

      select T2.cnyId
       , T2.wheId
       , T2.docKind
       , T2.docNum
       , T2.itmERPRefId
       , T2.invPartNum
       , T2.invPartDesc '

      IF (@multi_line = 1)
      BEGIN
        SET @sales_cmd +=
        N', sum(T2.itmQty)
         , sum(isnull(T3.itmQty1, 0.00)) '
      END
      ELSE
      BEGIN
        SET @sales_cmd +=
        N', T2.itmQty
         , isnull(T3.itmQty1, 0.00) '
      END

      SET @sales_cmd +=

      -- T2 alias a el documento de origen Barcode
      -- T3 alias a el documento de origen Sap

      -- La idea del alias T3 es para leer el impuesto enviado desde Sap
      -- ya que Barcode no incluye impuesto al cerrar el documento

      N', T2.itmPrice
       , 0
       , T2.itmERPRefNum
      from BBIL.dbo.BILDocumentItems T2
        left join BBIL.dbo.BILDocumentItems T3
                    on T3.invPartNum = T2.invPartNum
                    and T3.itmERPRefId = T2.itmERPRefId
          and T3.docId = ' + CAST(@cur_docrel AS varchar(15)) +
      ' where T2.docKind = ''SO''
                    and T2.docId = ' + CAST(@cur_docid AS varchar(15))

      SET @sales_cmd +=
      N' group by T2.itmERPRefId
       , T2.cnyId
       , T2.wheId
       , T2.docKind
       , T2.docNum
       , T2.invPartNum
       , T2.invPartDesc '

            IF (@multi_line = 0)
            BEGIN
             SET @sales_cmd +=
             N', T2.itmQty
             , T3.itmQty1 '
            END

            SET @sales_cmd +=
            N', T2.itmPrice
            , T2.itmERPRefNum

            order by T2.itmERPRefId '

      -- Cabeza

      SET @sales_cmd +=
      N'insert into B1BBIL.dbo.Document
        select T1.cnyId
        , T1.wheId
        , T1.docKind
        , T1.docNum
        , T1.docDate
        , T1.cstCode
        , T1.supCode
        , T1.docNotes
        , T1.docTotal
        , T1.docERPrefId
        , T1.docERPRefNum
        , 99
        , NULL
        from BBIL.dbo.BILDocuments T1
        where T1.docKind = ''SO''
          and T1.docOrigin = ''B''
          and T1.docStatus = ''CLOSED''
          and T1.docId = ' + CAST(@cur_docid AS varchar(15))

      -- Ejecutar
      EXECUTE sp_sqlexec @sales_cmd

      SET @min_saledocs =
      (
                SELECT MIN(T1.bilRowId) 'bilRowId'
          FROM BBIL.dbo.BILDocuments T1
            LEFT JOIN BBIL.dbo.BILDocuments T2 ON T2.docId = T1.docRelatedTo
          WHERE T1.docKind = 'SO'
            AND T1.docStatus = 'CLOSED'
            AND T1.docOrigin = 'B'
            AND T1.cstCode != 'CWW'
            AND T2.supCode IS NULL
            AND RTRIM(T1.docNum) NOT IN
            (
                        SELECT docNum
                        FROM B1BBIL.dbo.Document
                        WHERE docKind = 'SO'
                            AND cstCode = T1.cstCode
                            AND supCode IS NULL
                            AND wheId = T1.wheId
                            --// Mejora seek time
                            AND docNum = T1.docNum
                    )
      )
    END

        /*
            PEDIDOS INTERNO

            Trabajo por Tecnologia y Desarrollo
            © 2014/TARGET S.A.

            Creado: 07/02/2014

            Descripcion:
                El codigo funciona para que capture todo los documentos de venta, pedidos, cerrados por Barcode Box, con una
                peculiaridad: supCode es PI-CWW y cstCode es CWW.

            Change Log
                18/03/2014 - Zahir Gudiño
                    + Remover rtrim(docId) ya que no es necesario para campos int.
                    + Cambio de single comment a block comment en el bloque informativo del codigo.

                03/04/2014 - Zahir Gudino
                    + Mejora en el script radicalmente. Se consolidaron 2 casos:
                        a. Donde el documento cerrado por Barcode hay LineNum repetidos se consolidan las lineas repetidas
                                se suman itmQty y itmQty1.

                        b. Donde el documento cerrado por Barcode no aya LineNum repetidos se respete cada linea con su valor asignado.

                13/08/2014 -  Zahir Gudiño
                    + Reforzamos la relacion entre alias (documento maestro) y tabla actual (documento manual) para que
                        sum(T2.itmQty) no sume la cantidad de articulos en alias.

                        @@add
                            and T3.itmERPRefId = T2.itmERPRefId

                28/01/2015 - Zahir Gudino
                    + Unificar B1BBIL para todos los BarcodeBox utilizando SERVSAPDB.
                    + Filtro wheId para evitar conflicto con otros docNum.

        */

    DECLARE @min_in_saledocs int,
      @cur_in_docid int,
      @cur_in_docrel int,
      @multi_in_line int,
      @in_sales_cmd nvarchar(max)

    --// Buscar el primer bilRowId minimo segun el filtro
    SET @min_in_saledocs =
    (
      SELECT MIN (T1.bilRowId) 'bilRowId'
      FROM BBIL.dbo.BILDocuments T1
        LEFT JOIN BBIL.dbo.BILDocuments T2
                    ON T2.docId = T1.docRelatedTo
      WHERE T1.docKind = 'SO'
        AND T1.docStatus = 'CLOSED'
        AND T1.docOrigin = 'B'
        AND T1.cstCode = 'CWW'
        AND T2.supCode IS NOT NULL
        AND RTRIM(T1.docNum) NOT IN
        (
                    SELECT docNum
                    FROM B1BBIL.dbo.Document
          WHERE docKind = 'SO'
                        AND cstCode = T1.cstCode
                        AND supCode IS NOT NULL
                        AND docNum = T1.docNum
                        AND wheId = T1.wheId --// Bodega A
        )
    )

    WHILE @min_in_saledocs IS NOT NULL
    BEGIN

      --// Buscar docNum y docRelatedTo
      SELECT @cur_in_docid = docId
        , @cur_in_docrel = docRelatedTo
      FROM BBIL.dbo.BILDocuments
      WHERE bilRowId = @min_in_saledocs

      --// Revisar si docNum en detalles tiene mas de 1 lineNum
      IF EXISTS (
        SELECT itmERPRefId
        FROM BBIL.dbo.BILDocumentItems
        WHERE docId = @cur_in_docid
        GROUP BY itmERPRefId
        HAVING COUNT (itmErpRefId) > 1
      )
      BEGIN
        -- @multi_line = 1 si {n} > 1
        -- quiere decir que si hay lineas
        SET @multi_in_line = 1
      END
      ELSE
      BEGIN
        -- de lo contrario {n} < 1
        -- quiere decir que lineNum no esta repetido
        SET @multi_in_line = 0
      END

      SET @in_sales_cmd =
      N'
      insert into B1BBIL.dbo.DocumentLine
       (cnyId
       ,wheId
       ,docKind
       ,docNum
       ,LineNum
       ,invPartNum
       ,invPartDesc
       ,itmQty
       ,itmTax
       ,itmPrice
       ,itmERPRefId
       ,itmERPRefNum)

      select T2.cnyId
       , T2.wheId
       , T2.docKind
       , T2.docNum
       , T2.itmERPRefId
       , T2.invPartNum
       , T2.invPartDesc '

      IF (@multi_in_line = 1)
      BEGIN
        SET @in_sales_cmd +=
        N', sum(T2.itmQty)
         , sum(isnull(T3.itmQty1, 0.00)) '
      END
      ELSE
      BEGIN
        SET @in_sales_cmd +=
        N', T2.itmQty
         , isnull(T3.itmQty1, 0.00) '
      END

      SET @in_sales_cmd +=

      -- T2 alias a el documento de origen Barcode
      -- T3 alias a el documento de origen Sap

      -- La idea del alias T3 es para leer el impuesto enviado desde Sap
      -- ya que Barcode no incluye impuesto al cerrar el documento

      N', T2.itmPrice
       , 0
       , T2.itmERPRefNum
      from BBIL.dbo.BILDocumentItems T2
        left join BBIL.dbo.BILDocumentItems T3
                    on T3.invPartNum = T2.invPartNum
                    and T3.itmERPRefId = T2.itmERPRefId
          and T3.docId = ' + CAST(@cur_in_docrel AS varchar(15)) +
      ' where T2.docKind = ''SO''
                    and T2.docId = ' + CAST(@cur_in_docid AS varchar(15))

        SET @in_sales_cmd +=
        N' group by T2.itmERPRefId
         , T2.cnyId
         , T2.wheId
         , T2.docKind
         , T2.docNum
         , T2.invPartNum
         , T2.invPartDesc '

         IF (@multi_in_line = 0)
         BEGIN
           SET @in_sales_cmd +=
           N', T2.itmQty
           , T3.itmQty1 '
         END

         SET @in_sales_cmd +=
         N', T2.itmPrice
          , T2.itmERPRefNum

                order by T2.itmERPRefId '

      SET @in_sales_cmd +=
      N'insert into B1BBIL.dbo.Document
        select T1.cnyId
        , T1.wheId
        , T1.docKind
        , T1.docNum
        , T1.docDate
        , T1.cstCode
        , T2.supCode
        , T1.docNotes
        , T1.docTotal
        , T1.docERPrefId
        , T1.docERPRefNum
        , 99
        , NULL
        from BBIL.dbo.BILDocuments T1
                    inner join BBIL.dbo.BILDocuments T2
                        on T2.docId = ' + CAST(@cur_in_docrel AS varchar(15)) +
        ' where T1.docKind = ''SO''
                        and T1.docOrigin = ''B''
                        and T1.docStatus = ''CLOSED''
                        and T1.docId = ' + CAST(@cur_in_docid AS varchar(15))

      EXECUTE sp_sqlexec @in_sales_cmd

      --// Reiniciar el contador con el siguiente documento
      SET @min_in_saledocs =
      (
        SELECT MIN (T1.bilRowId) 'bilRowId'
        FROM BBIL.dbo.BILDocuments T1
          INNER JOIN BBIL.dbo.BILDocuments T2 ON T2.docId = T1.docRelatedTo
        WHERE T1.docKind = 'SO'
          AND T1.docStatus = 'CLOSED'
          AND T1.docOrigin = 'B'
          AND T1.cstCode = 'CWW'
          AND T2.supCode IS NOT NULL
          AND rtrim(T1.docNum) NOT IN
          (
                        SELECT docNum
                        FROM B1BBIL.dbo.Document
              WHERE docKind = 'SO'
                            AND cstCode = T1.cstCode
                            AND supCode IS NOT NULL
                            AND docNum = T1.docNum
                            AND wheId = T1.wheId --// Bodega A
          )
      )
    END

    UPDATE B1BBIL.dbo.Document
    SET Status= 0
    WHERE Status= 99

    COMMIT TRAN INSERT_TRANS_IN_BBIL;

END TRY
  BEGIN CATCH
        ROLLBACK TRAN INSERT_TRANS_IN_BBIL;

        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_SEVERITY() AS ErrorSeverity,
            ERROR_STATE() AS ErrorState,
            ERROR_PROCEDURE() AS ErrorProcedure,
            ERROR_LINE() AS ErrorLine,
            ERROR_MESSAGE() AS ErrorMessage;

END CATCH

GO

