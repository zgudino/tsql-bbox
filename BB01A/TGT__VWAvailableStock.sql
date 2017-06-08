IF EXISTS
(
	SELECT *
	FROM sys.objects
	WHERE object_id = OBJECT_ID('TGT__VWAvailableStock', 'V')
)
DROP VIEW TGT__VWAvailableStock
GO

CREATE VIEW TGT__VWAvailableStock
AS

SELECT a.invPartNum,
a.pakId,
a.stoQty,
a.stoID,
a.locID,
b.locKind,
b.locStorageMode,
b.cstId,
c.cstName
FROM Stock a
    LEFT JOIN Locations b ON b.locId = a.locId
        AND b.rowStatus = 'A'
    LEFT JOIN BB01..Customers c ON c.cstId = b.cstId
        AND c.rowStatus = 'A'
WHERE a.stoQty <> 0
    AND b.locStockIsAvailable = 1
    AND b.locStatus = 'ACTIVE'
