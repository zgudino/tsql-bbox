IF EXISTS
  (SELECT *
   FROM sys.objects
   WHERE object_id = OBJECT_ID(N'SPSyncTaskItems')
     AND OBJECTPROPERTY(OBJECT_ID(N'SPSyncTaskItems'), N'IsProcedure') = 1)
DROP PROCEDURE SPSyncTaskItems
GO

CREATE procedure [dbo].[SPSyncTaskItems]
@transType char(1),
@cnyId int,
@whsId char(1),
@tblHead varchar(max),
@itemCode varchar(255),
@debugEnabled bit = 0,
@stateId int output
AS

/*
    TARGET S.A
    ASL 2.0 © 2014

    Autor: Zahir Gudiño
    Correo: sistemas@conwaystore.com.pa

    Hecho en Panama <3
*/

DECLARE @cmdStr nvarchar(max)
DECLARE @parmStr nvarchar(500)

SET @cmdStr =
N'
DECLARE
@cnyId int,
@whsId char(1),
@barCode varchar(50),
@suppCatNum varchar(50),
@invPartNum varchar(50),
@invPartDesc varchar(50),
@pakId char(5),
@invBatched bit,
@rowStatus char(1),
@rowLastUpd datetime,
@rowUpdBy char(15),
@bilSynced bit,
@invSerialized bit,
@invERPFamilyCode varchar(50)

'

SET @cmdStr += N'
BEGIN TRY
    BEGIN TRANSACTION
'

/*
    18/04/2013
    + Transacciones "eliminar" ahora se inserta el regitro en vez de actualizar campos previo.

    11/11/2016
    + Modifico referencia de BBIL a BB01 por solicitud https://gitlab.com/zahir_gudino/bbox-synctasks/issues/3
*/

IF @transType IN ('U', 'D')
BEGIN
    IF (
        SELECT MAX(invPartNum)
        FROM [BB01].dbo.Inventory
        WHERE invPartNum = @itemCode
    ) IS NOT NULL
    BEGIN
        SET @cmdStr += N'
        SELECT @cnyId = ' + CAST(@cnyId AS char(1)) + ',
            @invPartNum = invPartNum,
            @invPartDesc = invPartDesc,
            @pakId = pakId,
            @invBatched = 0,
            @rowStatus = ''D'',
            @rowLastUpd = getdate(),
            @rowUpdBy = rowUpdBy,
            @bilSynced = 0,
            @invSerialized = 0,
            @invERPFamilyCode = invERPFamilyCode
        FROM [BB01].dbo.Inventory
        WHERE invPartNum = ' + QUOTENAME(@itemCode, '''') + '

        INSERT INTO [BBIL].dbo.BILInventoryParts (
            cnyId,
            invPartNum,
            invPartDesc,
            pakId,
            invBatched,
            invSerialized,
            rowStatus,
            rowLastUpd,
            rowUpdBy,
            bilSynced,
            invERPFamilyCode
        )
        VALUES (
            @cnyId,
            @invPartNum,
            @invPartDesc,
            @pakId,
            @invBatched,
            @invSerialized,
            @rowStatus,
            @rowLastUpd,
            @rowUpdBy,
            @bilSynced,
            @invERPFamilyCode
        )

        INSERT INTO [BBIL].dbo.BILBarcodes (
            cnyId,
            invPartNum,
            pakId,
            barCode,
            rowStatus,
            rowLastUpd,
            rowUpdBy,
            bilSynced
        )
        (
            SELECT DISTINCT @cnyId,
                invPartNum,
                pakId,
                barCode,
                @rowStatus,
                @rowLastUpd,
                @rowUpdBy,
                @bilSynced
            FROM [BB01].dbo.barCodes
            WHERE invPartNum = ' + QUOTENAME(@itemCode, '''')  + '
                AND rowStatus = ''A''
        )

        '
    END
END

IF @transType IN ('A', 'U')
BEGIN
    /*
        [MAESTRO DE PARTES]

        10/10/2014 (Zahir Gudiño)
            + Cambio de unida de medida de BuyUnitMsr a SalUnitMsr
    */

    SET @cmdStr += N'
    SELECT @cnyId = ' + CAST(@cnyId AS char(1)) + ',
        @whsId = ' + QUOTENAME(@whsId, '''') + ',
        @invPartNum = ItemCode,
        @barCode = CodeBars,
        @suppCatNum = suppCatNum,
        @invPartDesc = ISNULL(ItemName, @invPartNum),
        @pakId = SalUnitMsr,
        @invBatched = 0,
        @rowStatus = ''A'',
        @rowLastUpd = getdate(),
        @rowUpdBy = ''SAP'',
        @bilSynced = 0,
        @invSerialized = 0,
        @invERPFamilyCode = ItmsGrpCod
    FROM ' + @tblHead + '
    WHERE ItemCode = ' + QUOTENAME(@itemCode, '''') + '

    INSERT INTO [BBIL].dbo.BILCustomActions (
        actOrigin,
        cnyId,
        wheId,
        actCode,
        actCustom1,
        actCustom2,
        bilSynced,
        rowLastUpd,
        rowUpdBy
    )
    VALUES (
        ''C'',
        @cnyId,
        @whsId,
        1,
        @invPartNum,
        @pakId,
        @bilSynced,
        @rowLastUpd,
        @rowUpdBy
    )

    INSERT INTO [BBIL].dbo.BILInventoryParts (
        cnyId,
        invPartNum,
        invPartDesc,
        pakId,
        invBatched,
        invSerialized,
        rowStatus,
        rowLastUpd,
        rowUpdBy,
        bilSynced,
        invERPFamilyCode
    )
    VALUES (
        @cnyId,
        @invPartNum,
        @invPartDesc,
        @pakId,
        @invBatched,
        @invSerialized,
        @rowStatus,
        @rowLastUpd,
        @rowUpdBy,
        @bilSynced,
        @invERPFamilyCode
    )

    INSERT INTO [BBIL].dbo.BILBarcodes (
        cnyId,
        invPartNum,
        pakId,
        barCode,
        rowStatus,
        rowLastUpd,
        rowUpdBy,
        bilSynced
    )
    VALUES (
        @cnyId,
        @invPartNum,
        @pakId,
        @invPartNum,
        @rowStatus,
        @rowLastUpd,
        @rowUpdBy,
        @bilSynced
    )

    INSERT INTO [BBIL].dbo.BILBarcodes (
        cnyId,
        invPartNum,
        pakId,
        barCode,
        rowStatus,
        rowLastUpd,
        rowUpdBy,
        bilSynced
    )
    VALUES (
        @cnyId,
        @invPartNum,
        @pakId,
        @barCode,
        @rowStatus,
        @rowLastUpd,
        @rowUpdBy,
        @bilSynced
    )

    IF (@suppCatNum IS NOT NULL OR @suppCatNum <> '' '')
        AND @suppCatNum != @barCode
    BEGIN
        INSERT INTO [BBIL].dbo.BILBarcodes (
            cnyId,
            invPartNum,
            pakId,
            barCode,
            rowStatus,
            rowLastUpd,
            rowUpdBy,
            bilSynced
        )
        VALUES (
            @cnyId,
            @invPartNum,
            @pakId,
            @suppCatNum,
            @rowStatus,
            @rowLastUpd,
            @rowUpdBy,
            @bilSynced
        )
    END

    '
END

SET @cmdStr += N'
    SET @state_out = 1

    COMMIT TRANSACTION
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION
END CATCH
'
IF @debugEnabled <> 1
BEGIN
    SET @parmStr = N'@state_out int output'
    EXECUTE sp_executesql @cmdStr, @parmStr, @state_out = @stateId output
END
ELSE SELECT @cmdStr
