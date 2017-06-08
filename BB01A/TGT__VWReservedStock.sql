IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID('TGT__VWReservedStock', 'V')
)
DROP VIEW TGT__VWReservedStock
GO

SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
GO

CREATE VIEW TGT__VWReservedStock
AS

SELECT a.invPartNum,
a.pakId,
a.itmQty,
a.docId,
a.itmId,
b.docNum,
b.docKind,
b.docERPRefNum,
b.docDate,
b.cstId,
c.cstName
FROM Items a
    LEFT JOIN Documents b ON b.docId = a.docId
    LEFT JOIN BB01..Customers c ON c.cstId = b.cstID
WHERE a.rowStatus = 'A'
    AND b.docKind IN ('SO','PR')
    AND a.itmStatus = 'ACTIVE'
    AND b.docStatus IN ('DRAFT','PENDING')
