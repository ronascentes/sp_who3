/*********************************************************************************************************************************************************
Ultimate_health_check.sql
Quick health check for production databases. 
Created by Rodrigo Nascentes @ronascentes (12-DEC-2016)
Last modified: 12-DEC-2016
References: 
http://sqlskills.com/blogs/glenn SQL Server Diagnostic Information Queries - Copyright (C) 2016 Glenn Berry, SQLskills.com - All rights reserved.
https://github.com/Microsoft/tigertoolbox MSSQL Tiger team toolbox 

**********************************************************************************************************************************************************/
USE [master]
GO
SET NOCOUNT ON;
SET ANSI_WARNINGS ON;
SET QUOTED_IDENTIFIER ON;
SET DATEFORMAT mdy;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

/************** SQL and OS version ************************************************************************************************************************/
SELECT @@SERVERNAME AS [Server Name], @@VERSION AS [SQL Server and OS Version Info]


/************** Uptime information ************************************************************************************************************************/
SELECT 'Uptime' AS [Category], sqlserver_start_time, CONVERT(VARCHAR(4),DATEDIFF(mi,sqlserver_start_time,GETDATE())/60/24) + 'd ' + CONVERT(VARCHAR(4),DATEDIFF(mi,sqlserver_start_time,GETDATE())/60%24) + 'hr ' + CONVERT(VARCHAR(4),DATEDIFF(mi,sqlserver_start_time,GETDATE())%60) + 'min' AS Uptime FROM sys.dm_os_sys_info (NOLOCK)
GO

/************** AlwayOn information ************************************************************************************************************************/
IF (SELECT SERVERPROPERTY('IsHadrEnabled')) = 1
BEGIN	
	SELECT 'AlwaysOn_Status' as [Category], ag.name AS ag_name, ars.role_desc, ar.replica_server_name, adc.database_name,
	d.log_reuse_wait_desc, drs.database_state_desc, ar.availability_mode_desc, drs.synchronization_state_desc, 
	drs.synchronization_health_desc, drs.redo_queue_size, ars.connected_state_desc, 
	ars.operational_state_desc, ars.recovery_health_desc, drs.last_commit_time, 
	datediff(s,last_hardened_time,getdate()) as 'sec behind primary'
	FROM sys.databases d
	JOIN sys.dm_hadr_database_replica_states AS drs WITH (NOLOCK) ON d.database_id=drs.database_id
	JOIN sys.availability_databases_cluster AS adc WITH (NOLOCK) ON drs.group_id = adc.group_id AND drs.group_database_id = adc.group_database_id
	JOIN sys.availability_groups AS ag WITH (NOLOCK) ON ag.group_id = drs.group_id
	JOIN sys.availability_replicas AS ar WITH (NOLOCK) ON drs.group_id = ar.group_id AND drs.replica_id = ar.replica_id
	JOIN sys.dm_hadr_availability_replica_states ars WITH (NOLOCK) ON ar.replica_id = ars.replica_id
	ORDER BY ars.role_desc ASC,	ag.name ASC, ar.replica_server_name ASC, adc.database_name ASC;
END;
GO

/************** ADVANCED SETTINGS ************************************************************************************************************************/
-- priority boost (should be zero)
SELECT 'Advanced_Settings' as [Category], name, value, value_in_use
FROM sys.configurations WITH (NOLOCK)
WHERE configuration_id IN (518,1538,1539,1544,1581,1517)
GO

/************** Trace flags ************************************************************************************************************************/
-- TF1118 turns off mixed page allocations. Preventing mixed page allocations reduces the risk of page latch contention 
-- on the SGAM allocation bitmatps that track mixed extents; which Paul says is one of the leading causes for contention in tempdb.
-- When doing allocations for user tables always allocate full extents.  Reducing contention of mixed extent allocations

-- TF3226 simply stops SQL Server from writing backup successful messages to the error log.

-- TF2371 changes to automatic update statistics

-- TF1117 When growing a data file grow all files at the same time so they remain the same size, reducing allocation contention points.
--  applies to the entire SQL Server instance, not just to one DB and it affects all files in the same filegroup in a database

-- TF4199 sQL Server query optimizer hotfix servicing model https://support.microsoft.com/en-us/kb/974006

-- Usage: DBCC TRACEON (<TF#>,-1)
DBCC TRACESTATUS (1118,3226,2371,4199);  
GO

/************** Task counts ************************************************************************************************************************/
-- Get Average Task Counts (run multiple times)
-- Sustained values above 10 suggest further investigation in that area
-- High current_tasks_count is often an indication of locking/blocking problems
-- High runnable_tasks_count is an indication of CPU pressure
-- High pending_disk_io_count is an indication of I/O pressure
SELECT 'Tasks_Count' as [Category], AVG(current_tasks_count) AS [Avg Task Count], 
AVG(runnable_tasks_count) AS [Avg Runnable Task Count],
AVG(pending_disk_io_count) AS [AvgPendingDiskIOCount]
FROM sys.dm_os_schedulers WITH (NOLOCK)
WHERE scheduler_id < 255;
GO

/************** CPU ************************************************************************************************************************/
WITH DB_CPU_Stats
AS
(SELECT DatabaseID, DB_Name(DatabaseID) AS [DatabaseName], SUM(total_worker_time) AS [CPU_Time_Ms]
 FROM sys.dm_exec_query_stats AS qs WITH (NOLOCK)
 CROSS APPLY (SELECT CONVERT(int, value) AS [DatabaseID] 
              FROM sys.dm_exec_plan_attributes(qs.plan_handle)
              WHERE attribute = N'dbid') AS F_DB
 GROUP BY DatabaseID)
SELECT 'DB_CPU' as [Category], ROW_NUMBER() OVER(ORDER BY [CPU_Time_Ms] DESC) AS [row_num],
       DatabaseName, [CPU_Time_Ms], 
       CAST([CPU_Time_Ms] * 1.0 / SUM([CPU_Time_Ms]) OVER() * 100.0 AS DECIMAL(5, 2)) AS [CPUPercent]
FROM DB_CPU_Stats
WHERE DatabaseID > 4 -- system databases
AND DatabaseID <> 32767 -- ResourceDB
ORDER BY row_num;
GO

-- Get CPU trend for pass 256 min 
declare @ts_now bigint
select @ts_now = cpu_ticks / (cpu_ticks/ms_ticks) from sys.dm_os_sys_info;  
select TOP(15) 'CPU_Trend' as [Category],record_id,
      dateadd(ms, -1 * (@ts_now - [timestamp]), GetDate()) as EventTime,
      SQLProcessUtilization,
      SystemIdle,
      100 - SystemIdle - SQLProcessUtilization as OtherProcessUtilization
from (
      select
            record.value('(./Record/@id)[1]', 'int') as record_id,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') as SystemIdle,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') as SQLProcessUtilization,
            timestamp
      from (
            select timestamp, convert(xml, record) as record
            from sys.dm_os_ring_buffers
            where ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            and record like '%<SystemHealth>%') as x
      ) as y
order by record_id desc

/************** look for usually errors at errorlog ************************************************************************************************************************/
exec xp_readerrorlog 0, 1, N'SQL Server is starting at high priority base',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'fatal exception ',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'Deadlock encountered',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'deadlock-list',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'An error has occurred while establishing a connection to the server',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'fatal error',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'corruption',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'corrupted',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'The error log has been reinitalized',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'SQL Server is starting',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'Recovery of database',null,null,null, N'desc';
GO

/************** Memory ************************************************************************************************************************/
-- This query returns information about the state of the system (totals and available numbers) 
-- as well as the global state if the system detects low, high, or steady memory conditions. 
-- The "Available physical memory is low" indicator in the system_memory_state_desc column is 
-- another sign of external memory pressure that requires further investigation. 
-- Relieving external memory pressure by identifying and eliminating major physical memory 
-- consumers (if possible) and/or by adding more memory should generally resolve problems related to memory.
select 'Memory' as [Category], total_physical_memory_kb / 1024 as phys_mem_mb,
	   available_physical_memory_kb / 1024 as avail_phys_mem_mb,
	   system_cache_kb /1024 as sys_cache_mb,
	   (kernel_paged_pool_kb+kernel_nonpaged_pool_kb) / 1024 
		as kernel_pool_mb,
	total_page_file_kb / 1024 as total_page_file_mb,
	available_page_file_kb / 1024 as available_page_file_mb,
	system_memory_state_desc
from sys.dm_os_sys_memory WITH (NOLOCK) 
GO

-- SQL Server Process Address space info 
-- (shows whether locked pages is enabled, among other things)
-- You want to see 0 for process_physical_memory_low
-- You want to see 0 for process_virtual_memory_low
SELECT 'Memory' as [Category],physical_memory_in_use_kb,locked_page_allocations_kb, 
       page_fault_count, memory_utilization_percentage, 
       available_commit_limit_kb, process_physical_memory_low, 
       process_virtual_memory_low
FROM sys.dm_os_process_memory WITH (NOLOCK);
GO

-- Higher PLE is better. Watch the trend, not the absolute value.
-- Memory Grants Outstanding above zero for a sustained period is a very strong indicator of memory pressure
-- Memory Grants Pending above zero for a sustained period is a very strong indicator of memory pressure
-- Total Server Memory indicates the current size of the buffer pool
-- Target Server Memory indicates the ideal size for the buffer pool. Total and Traget should be the same.
-- If Total < Target, SQL cannot grow the buffer pool due to memonry pressure. Further investigation is required.
SELECT 'Memory' as [Category], [object_name],counter_name, cntr_value
FROM sys.dm_os_performance_counters WITH (NOLOCK)
WHERE([object_name] LIKE N'%Memory Manager%' AND counter_name LIKE N'Total Server Memory (KB)%') 
OR ([object_name] LIKE N'%Memory Manager%' AND counter_name LIKE N'Target Server Memory (KB)%') 
OR ([object_name] LIKE N'%Buffer Manager%' AND counter_name = N'Page life expectancy')
OR ([object_name] LIKE N'%Memory Manager%' AND counter_name = N'Memory Grants Outstanding')
OR ([object_name] LIKE N'%Memory Manager%' AND counter_name = N'Memory Grants Pending') 
GO

-- Insufficient memory issues: http://support.microsoft.com/kb/309256 or https://support.microsoft.com/kb/2001221
exec xp_readerrorlog 0, 1, N'A time out occurred while waiting for memory resources to execute the query',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'A There is insufficient system memory to run this query',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'A significant part of sql server memory has been paged out',null,null,null, N'desc';
GO

/************** IO ************************************************************************************************************************/
-- LUNS information
SELECT DISTINCT 'Disk_Space' AS [Category],vs.volume_mount_point, vs.file_system_type, 
vs.logical_volume_name, CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0) AS [Total Size (GB)],
CONVERT(DECIMAL(18,2),vs.available_bytes/1073741824.0) AS [Available Size (GB)],  
CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,2)) * 100 AS [Space Free %] 
FROM sys.master_files AS f WITH (NOLOCK)
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs
GO

-- get I/O latency for all databases
-- any value < 20 ms is acceptable for data files
-- any value < 15 ms is acceptable for log files
SELECT 'IO_Latency' as [Category],DB_NAME(fs.database_id) AS [Database Name], mf.physical_name,
        io_stall_read_ms / num_of_reads AS 'Avg Read Transfer/ms',
        io_stall_write_ms / num_of_writes AS 'Avg Write Transfer/ms'
FROM sys.dm_io_virtual_file_stats(null,null) AS fs 
INNER JOIN sys.master_files AS mf
ON fs.database_id = mf.database_id
AND fs.[file_id] = mf.[file_id]
WHERE   num_of_reads > 0
    AND num_of_writes > 0
OPTION (RECOMPILE);
GO

exec xp_readerrorlog 0, 1, N'occurrence(s) of I/O requests taking longer than 15 seconds to complete on file',null,null,null, N'desc';
GO

SELECT 'Tempdb_Usage' as [Category], SUM(user_object_reserved_page_count) AS user_object_pages,
        SUM(internal_object_reserved_page_count) AS internal_object_pages,
        SUM(version_store_reserved_page_count) AS version_store_pages,
        total_in_use_pages = SUM(user_object_reserved_page_count)
        + SUM(internal_object_reserved_page_count)
        + SUM(version_store_reserved_page_count),
        SUM(unallocated_extent_page_count)/(128*1024) AS total_free_space_GB
FROM   tempdb.sys.dm_db_file_space_usage WITH (NOLOCK);
GO

-- check last DBCC CHECKDB successfully
IF OBJECT_ID('tempdb..#checkdb') IS NOT NULL 
	DROP TABLE #checkdb;
CREATE TABLE #checkdb (
ParentObject VARCHAR(255),
Object VARCHAR(255),
Field VARCHAR(255),
Value VARCHAR(255),
DbName NVARCHAR(128) NULL
)
EXEC sp_MSforeachdb 
N'USE [?];
INSERT #checkdb
    (ParentObject, Object, Field, Value)
EXEC (''DBCC DBInfo() With TableResults, NO_INFOMSGS'');
UPDATE #checkdb SET DbName = N''?'' WHERE DbName IS NULL;';

SELECT DISTINCT 'Last DBCC CHECKDB' as [Category], DBName, Value as [Last DBCC CHECKDB sucessfully]     
        FROM     #checkdb
        WHERE    Field = 'dbi_dbccLastKnownGood'
		AND dbname NOT IN ('master','model','msdb','tempdb')

DROP TABLE #checkdb
GO

/************** System Health Session ************************************************************************************************************************/
-- check system health session
IF EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#SystemHealthSessionData'))
DROP TABLE #SystemHealthSessionData;
IF NOT EXISTS (SELECT [object_id] FROM tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#SystemHealthSessionData'))
CREATE TABLE #SystemHealthSessionData (target_data XML)
		
-- Store the XML data in a temporary table
INSERT INTO #SystemHealthSessionData
SELECT CAST(xet.target_data AS XML)
FROM sys.dm_xe_session_targets xet
INNER JOIN sys.dm_xe_sessions xe ON xe.address = xet.event_session_address
WHERE xe.name = 'system_health'
	
IF (SELECT COUNT(*) FROM #SystemHealthSessionData a WHERE CONVERT(VARCHAR(max), target_data) LIKE '%error_reported%') > 0
BEGIN
	-- Get statistical information about all the errors reported
	;WITH cteHealthSession (EventXML) AS (SELECT C.query('.') EventXML
		FROM #SystemHealthSessionData a
		CROSS APPLY a.target_data.nodes('/RingBufferTarget/event') AS T(C)
	),
	cteErrorReported (EventTime, ErrorNumber) AS (SELECT EventXML.value('(/event/@timestamp)[1]', 'datetime') AS EventTime,
		EventXML.value('(/event/data[@name="error_number"]/value)[1]', 'int') AS ErrorNumber
		FROM cteHealthSession
		WHERE EventXML.value('(/event/@name)[1]', 'VARCHAR(500)') = 'error_reported'
	)
	SELECT 'System_health_session' as [Category],
		ErrorNumber AS [Error_Number],
		MIN(EventTime) AS [First_Logged_Date],
		MAX(EventTime) AS [Last_Logged_Date],
		COUNT(ErrorNumber) AS Error_Count,
		REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(b.text,'%.*ls','%'),'%d','%'),'%ls','%'),'%S_MSG','%'),'%S_PGID','%'),'%#016I64x','%'),'%p','%'),'%08x','%'),'%u','%'),'%I64d','%'),'%s','%'),'%ld','%'),'%lx','%'), '%%%', '%') AS [Look_for_Message_example] 
	FROM cteErrorReported a
	INNER JOIN sys.messages b ON a.ErrorNumber = b.message_id
	WHERE b.language_id = 1033
	GROUP BY a.ErrorNumber, b.[text]
				
	-- Get detailed information about all the errors reported
	;WITH cteHealthSession AS (SELECT C.query('.').value('(/event/@timestamp)[1]', 'datetime') AS EventTime,
		C.query('.').value('(/event/data[@name="error_number"]/value)[1]', 'int') AS ErrorNumber,
		C.query('.').value('(/event/data[@name="severity"]/value)[1]', 'int') AS ErrorSeverity,
		C.query('.').value('(/event/data[@name="state"]/value)[1]', 'int') AS ErrorState,
		C.query('.').value('(/event/data[@name="message"]/value)[1]', 'VARCHAR(MAX)') AS ErrorText,
		C.query('.').value('(/event/action[@name="session_id"]/value)[1]', 'int') AS SessionID,
		C.query('.').value('(/event/data[@name="category"]/text)[1]', 'VARCHAR(10)') AS ErrorCategory
		FROM #SystemHealthSessionData a
		CROSS APPLY a.target_data.nodes('/RingBufferTarget/event') AS T(C)
		WHERE C.query('.').value('(/event/@name)[1]', 'VARCHAR(500)') = 'error_reported')
	SELECT  'System_health_session' as [Category],
		EventTime AS [Logged_Date],
		ErrorNumber AS [Error_Number],
		ErrorSeverity AS [Error_Sev],
		ErrorState AS [Error_State],
		ErrorText AS [Logged_Message],
		SessionID
	FROM cteHealthSession
	ORDER BY EventTime
END
ELSE
BEGIN
	SELECT 'No SystemHealth_Errors found' AS [Check]
END;
GO

