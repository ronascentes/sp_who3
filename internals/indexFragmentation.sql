SET NOCOUNT ON
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
GO
WITH index_defrag(object_name, schemaname, index_name, avg_frag) AS
(SELECT 
       Quotename(o.name)                  AS object_name, 
       Quotename(s.name)                  AS schemaname, 
       i.name                             AS index_name, 
	   stats.avg_fragmentation_in_percent AS avg_frag
FROM   sys.Dm_db_index_physical_stats(Db_id(), NULL, NULL, NULL, 'LIMITED') stats                           -- at database level
-- FROM sys.Dm_db_index_physical_stats(Db_id(), object_id ('table_name'), NULL, NULL, 'LIMITED') stats      -- at table level
JOIN sys.objects o
	ON o.object_id = stats.object_id
JOIN sys.schemas s
	ON s.schema_id = o.schema_id 
JOIN sys.indexes i
	ON i.object_id = stats.object_id 
	AND i.index_id = stats.index_id 
WHERE stats.avg_fragmentation_in_percent >= 10.0 
       AND stats.page_count >= 5000 
       AND stats.index_id > 0)
SELECT 'ALTER INDEX ' + '[' + index_name + ']' + ' ON ' + '[' + object_name + ']' + ' ' + 
		CASE 
         WHEN avg_frag < 30 THEN 'REORGANIZE' 
         WHEN avg_frag > 30 THEN 'REBUILD WITH(MAXDOP=4)'                                                   --take advantage of parallelism
       END 
FROM index_defrag
GO



SELECT DB_NAME(), s.name, o.name, i.[object_id], i.name, stats.avg_fragmentation_in_percent, stats.index_type_desc, stats.alloc_unit_type_desc	
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') stats
JOIN sys.objects o WITH (NOLOCK) ON o.object_id = stats.object_id
JOIN sys.schemas s WITH (NOLOCK) ON s.schema_id = o.schema_id 
JOIN sys.indexes i WITH (NOLOCK) ON i.object_id = stats.object_id AND i.index_id = stats.index_id
WHERE stats.avg_fragmentation_in_percent >= 10.0 
AND stats.page_count >= 5000 
AND stats.index_id > 0
