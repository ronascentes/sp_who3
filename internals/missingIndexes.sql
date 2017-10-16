-- Find Missing Indexes by Index Advantage
-- Look at index advantage, last user seek time, number of user seeks to help determine source and importance
-- SQL Server is overly eager to add included columns, so beware
-- Do not just blindly add indexes that show up from this query!!!
SET NOCOUNT ON
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SELECT TOP 20
DB_NAME(dm_mid.database_id) AS Database_Name,
[User_Hits_on_Missing_Index] = (dm_migs.user_seeks + dm_migs.user_scans),
dm_migs.avg_user_impact, 							-- Query cost would reduce by this amount in percentage, on average.
dm_migs.avg_total_user_cost, 						-- Average cost of the user queries that could be reduced by the index in the group.
dm_migs.unique_compiles,							-- Number of compilations and recompilations that would benefit from this missing index group.
dm_migs.last_user_seek AS Last_User_Seek,
OBJECT_NAME(dm_mid.OBJECT_ID,dm_mid.database_id) AS [TableName],
'CREATE INDEX [IX_' + OBJECT_NAME(dm_mid.OBJECT_ID,dm_mid.database_id) + '_'
+ REPLACE(REPLACE(REPLACE(ISNULL(dm_mid.equality_columns,''),', ','_'),'[',''),']','') +
CASE
WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns IS NOT NULL THEN '_'
ELSE ''
END
+ REPLACE(REPLACE(REPLACE(ISNULL(dm_mid.inequality_columns,''),', ','_'),'[',''),']','')
+ ']'
+ ' ON ' + dm_mid.statement
+ ' (' + ISNULL (dm_mid.equality_columns,'')
+ CASE WHEN dm_mid.equality_columns IS NOT NULL AND dm_mid.inequality_columns IS NOT NULL THEN ',' ELSE
'' END
+ ISNULL (dm_mid.inequality_columns, '')
+ ')'
+ ISNULL (' INCLUDE (' + dm_mid.included_columns + ')', '') AS Create_Statement
FROM sys.dm_db_missing_index_groups dm_mig WITH (NOLOCK)
INNER JOIN sys.dm_db_missing_index_group_stats dm_migs WITH (NOLOCK)
    ON dm_migs.group_handle = dm_mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details dm_mid WITH (NOLOCK)
    ON dm_mig.index_handle = dm_mid.index_handle
WHERE DB_NAME(dm_mid.database_ID) NOT IN ('msdb','master','tempdb','model', 'Dell_Maint')
ORDER BY Database_Name, dm_migs.avg_user_impact DESC OPTION (RECOMPILE);
GO



-- Find missing index warnings for cached plans in the current database
-- Note: This query could take some time on a busy instance
SELECT TOP(25) OBJECT_NAME(objectid) AS [ObjectName], 
               query_plan, cp.objtype, cp.usecounts
FROM sys.dm_exec_cached_plans AS cp WITH (NOLOCK)
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
WHERE CAST(query_plan AS NVARCHAR(MAX)) LIKE N'%MissingIndex%'
AND dbid = DB_ID()
ORDER BY cp.usecounts DESC OPTION (RECOMPILE);


-- copied from Performance Dashboard 2016
	select d.database_id, d.object_id, d.index_handle, d.equality_columns, d.inequality_columns, d.included_columns, d.statement as fully_qualified_object,
	gs.* 
	from sys.dm_db_missing_index_groups g
		join sys.dm_db_missing_index_group_stats gs on gs.group_handle = g.index_group_handle
		join sys.dm_db_missing_index_details d on g.index_handle = d.index_handle
	where d.database_id = isnull(@DatabaseID , d.database_id) and d.object_id = isnull(@ObjectID, d.object_id)
