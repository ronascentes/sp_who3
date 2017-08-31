-- Resource Pool utilization
 SELECT pool_id  
     , Name  
     , min_memory_percent  
     , max_memory_percent  
     , max_memory_kb/1024 AS max_memory_mb  
     , used_memory_kb/1024 AS used_memory_mb   
     , target_memory_kb/1024 AS target_memory_mb  
FROM sys.dm_resource_governor_resource_pools
GO
-- In memory table utilization
use <db_name>  
go
SELECT object_name(object_id) AS table_name, 
	memory_allocated_for_table_kb/1024 memory_allocated_for_table_mb,
	memory_used_by_table_kb/1024 memory_used_by_table_mb,
	memory_allocated_for_indexes_kb/1024 memory_allocated_for_indexes_mb,
	memory_used_by_indexes_kb/1024 memory_used_by_indexes_mb
FROM sys.dm_db_xtp_table_memory_stats
go
-- XTP usage (Same as XTP Memory Used in PERFMOM, counts Log pool utilization as well)
use <db_name>  
go
Select getdate() as DateTimeCaptured,sum(allocated_Bytes/(1024*1024)) As Total_XTP_Allocated_MB,
sum(Used_bytes/(1024*1024)) As Total_XTP_Used_MB,
(sum(allocated_Bytes/(1024*1024)) - sum(Used_bytes/(1024*1024))) As Free_XTP_Memory_MB
from sys.dm_db_xtp_memory_consumers

exec xp_readerrorlog 0, 1, N'A significant part of sql server memory has been paged out',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'memory',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'HK_E_OUTOFMEMORY',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'SQL Server is terminating because of a system shutdown',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'Always On: The availability replica manager is going offline',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'[ERROR]',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'FAIL_PAGE_ALLOCATION',null,null,null, N'desc';

