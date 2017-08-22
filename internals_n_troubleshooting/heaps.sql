-- Database has heaps, that’s, tables without clustered indexes. They’re scattered on disk anywhere that SQL Server can find a spot, and they’re not stored in any order whatsoever.
-- This can make for fast inserts but really slow selects, updates, and deletes. 
-- Unfortunatily there is no a fast fix: you need to determine the right clustering index, test in non-prod and validate the results. Please work with the dev team.
      SELECT DISTINCT
      ('The [' + DB_NAME() + '] database has heaps - tables without a clustered index - that are being actively queried.') 
      FROM sys.indexes i INNER JOIN sys.objects o ON i.object_id = o.object_id 
      INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id 
      INNER JOIN sys.databases sd ON sd.name = DB_NAME()
      LEFT OUTER JOIN sys.dm_db_index_usage_stats ius ON i.object_id = ius.object_id AND i.index_id = ius.index_id AND ius.database_id = sd.database_id 
      WHERE i.type_desc = 'HEAP' AND COALESCE(ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates) IS NOT NULL 
      AND sd.name <> 'tempdb' AND o.is_ms_shipped = 0 AND o.type <> 'S'