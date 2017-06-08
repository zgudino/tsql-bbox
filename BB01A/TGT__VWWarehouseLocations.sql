IF EXISTS
(
    SELECT *
    FROM sys.objects
    WHERE object_id = OBJECT_ID('TGT__VWWarehouseLocations', 'V')
)
DROP VIEW TGT__VWWarehouseLocations
GO

CREATE VIEW TGT__VWWarehouseLocations
AS

SELECT LOCID 'locId',
LOCKIND 'locKind',
LOCSTATUS 'locStatus'
FROM LOCATIONS
WHERE LOCKIND IN ('INDOCK', 'OUTDOCK', 'STORAGE')
    AND ROWSTATUS != 'D'
