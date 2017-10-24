/*********************************************************************************************************************************************************
Quick health check for production databases. 
Created by Rodrigo Nascentes @ronascentes (12-DEC-2016)
This script was optimized so that it should give acceptable results in 25s
References: 
http://sqlskills.com/blogs/glenn SQL Server Diagnostic Information Queries - Copyright (C) 2016 Glenn Berry, SQLskills.com - All rights reserved.
https://github.com/Microsoft/tigertoolbox MSSQL Tiger team toolbox 

**********************************************************************************************************************************************************/
USE [master]
GO

DECLARE @check_missing_indexes BIT, @check_top_queries BIT, @check_in_memory BIT;

SET NOCOUNT ON;
SET ANSI_WARNINGS ON;
SET QUOTED_IDENTIFIER ON;
SET DATEFORMAT mdy;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SET @check_missing_indexes = 0;
SET @check_in_memory = 1;
SET @check_top_queries = 0;

/************** SQL and OS version ************************************************************************************************************************/
SELECT @@SERVERNAME AS [Server Name], @@VERSION AS [SQL Server and OS Version Info];


/************** Uptime information ************************************************************************************************************************/
SELECT 'Uptime' AS [Category], sqlserver_start_time, CONVERT(VARCHAR(4),DATEDIFF(mi,sqlserver_start_time,GETDATE())/60/24) + 'd ' + CONVERT(VARCHAR(4),DATEDIFF(mi,sqlserver_start_time,GETDATE())/60%24) + 'hr ' + CONVERT(VARCHAR(4),DATEDIFF(mi,sqlserver_start_time,GETDATE())%60) + 'min' AS Uptime FROM sys.dm_os_sys_info (NOLOCK);


/************** AlwayOn information ************************************************************************************************************************/
IF (SELECT SERVERPROPERTY('IsHadrEnabled')) = 1
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
ELSE
	SELECT 'Mirroring' AS [Category], a.name, mirroring_state_desc, 
	mirroring_role_desc, mirroring_partner_instance, mirroring_partner_name
	FROM sys.databases a JOIN sys.database_mirroring b 
	ON a.database_id = b.database_id
	WHERE a.database_id > 4;


/************** ADVANCED SETTINGS ************************************************************************************************************************/
-- priority boost (should be zero)
SELECT 'Advanced_Settings' as [Category], name, value, value_in_use
FROM sys.configurations WITH (NOLOCK)
WHERE configuration_id IN (518,1538,1539,1544,1581,1517);


/************** Trace flags ************************************************************************************************************************/
-- TF1118 turns off mixed page allocations. Preventing mixed page allocations reduces the risk of page latch contention 
-- on the SGAM allocation bitmatps that track mixed extents; which Paul says is one of the leading causes for contention in tempdb.
-- When doing allocations for user tables always allocate full extents.  Reducing contention of mixed extent allocations
-- Starting with SQL Server 2016 this behavior is controlled by the SET MIXED_PAGE_ALLOCATION option of ALTER DATABASE, and trace flag 1118 has no affect. 

-- TF3226 simply stops SQL Server from writing backup successful messages to the error log.

-- TF2371 changes to automatic update statistics

-- TF1117 When growing a data file grow all files at the same time so they remain the same size, reducing allocation contention points.
--  applies to the entire SQL Server instance, not just to one DB and it affects all files in the same filegroup in a database

-- TF4199 SQL Server query optimizer hotfix servicing model https://support.microsoft.com/en-us/kb/974006 
-- Enabled by default in SQL 2016

-- Usage: 
-- DBCC TRACEON (1118,3226,2371,4199, -1);
IF EXISTS (select * from tempdb.sys.objects (NOLOCK) WHERE [object_id] = OBJECT_ID('tempdb.dbo.#trace_flag'))
  DROP TABLE #trace_flag;

-- Get the list of objects to defrag
CREATE TABLE #trace_flag(
	[TraceFlag] INT NULL,
	[Status] TINYINT NULL,
	[Global] TINYINT NULL,
	[Session] TINYINT NULL
)

INSERT INTO #trace_flag
EXEC ('DBCC TRACESTATUS (1118,3226,2371,4199) WITH NO_INFOMSGS')

SELECT TraceFlag, Status, Global, Session, N'turns off mixed page allocations. Reduces the risk of page latch contention on the SGAM allocation bitmatps that track mixed extents; which is one of the leading causes for contention in tempdb' AS [INFO] FROM #trace_flag WHERE TraceFlag = 1118
UNION
SELECT TraceFlag, Status, Global, Session, N'simply stops SQL Server from writing backup successful messages to the error log' AS [INFO] FROM #trace_flag WHERE TraceFlag = 3226
UNION
SELECT TraceFlag, Status, Global, Session, N'changes to automatic update statistics' AS [INFO] FROM #trace_flag WHERE TraceFlag = 2371
UNION
SELECT TraceFlag, Status, Global, Session, N'SQL Server query optimizer hotfix servicing model https://support.microsoft.com/en-us/kb/974006 Enabled by default in SQL 2016' AS [INFO] FROM #trace_flag WHERE TraceFlag = 4199
DROP TABLE #trace_flag;


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

-- Isolate top waits for server instance since last restart or wait statistics clear  (Query 34) (Top Waits)
WITH [Waits] 
AS (SELECT wait_type, wait_time_ms/ 1000.0 AS [WaitS],
          (wait_time_ms - signal_wait_time_ms) / 1000.0 AS [ResourceS],
           signal_wait_time_ms / 1000.0 AS [SignalS],
           waiting_tasks_count AS [WaitCount],
           100.0 *  wait_time_ms / SUM (wait_time_ms) OVER() AS [Percentage],
           ROW_NUMBER() OVER(ORDER BY wait_time_ms DESC) AS [RowNum]
    FROM sys.dm_os_wait_stats WITH (NOLOCK)
    WHERE [wait_type] NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
		N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT', N'DBMIRROR_EVENTS_QUEUE', N'DBMIRROR_WORKER_QUEUE',
		N'DBMIRRORING_CMD', N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC', N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL', N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT', 
		N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE', 
		N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',
		N'PREEMPTIVE_OS_LIBRARYOPS', N'PREEMPTIVE_OS_COMOPS', N'PREEMPTIVE_OS_CRYPTOPS',
		N'PREEMPTIVE_OS_PIPEOPS', N'PREEMPTIVE_OS_AUTHENTICATIONOPS',
		N'PREEMPTIVE_OS_GENERICOPS', N'PREEMPTIVE_OS_VERIFYTRUST',
		N'PREEMPTIVE_OS_FILEOPS', N'PREEMPTIVE_OS_DEVICEOPS',
        N'PWAIT_ALL_COMPONENTS_INITIALIZED', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
		N'QDS_ASYNC_QUEUE',
        N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP', N'REQUEST_FOR_DEADLOCK_SEARCH',
		N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK', N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP',
		N'SLEEP_DCOMSTARTUP', N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED', N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SP_SERVER_DIAGNOSTICS_SLEEP',
		N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP', N'SQLTRACE_WAIT_ENTRIES',
		N'WAIT_FOR_RESULTS', N'WAITFOR', N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_HOST_WAIT',
		N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG', N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN',
        N'XE_DISPATCHER_WAIT', N'XE_LIVE_TARGET_TVF', N'XE_TIMER_EVENT')
    AND waiting_tasks_count > 0)
SELECT
    'Top waits' AS [Category],
	MAX (W1.wait_type) AS [WaitType],
    CAST (MAX (W1.WaitS) AS DECIMAL (16,2)) AS [Wait_Sec],
    CAST (MAX (W1.ResourceS) AS DECIMAL (16,2)) AS [Resource_Sec],
    CAST (MAX (W1.SignalS) AS DECIMAL (16,2)) AS [Signal_Sec],
    MAX (W1.WaitCount) AS [Wait Count],
    CAST (MAX (W1.Percentage) AS DECIMAL (5,2)) AS [Wait Percentage],
    CAST ((MAX (W1.WaitS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgWait_Sec],
    CAST ((MAX (W1.ResourceS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgRes_Sec],
    CAST ((MAX (W1.SignalS) / MAX (W1.WaitCount)) AS DECIMAL (16,4)) AS [AvgSig_Sec]
FROM Waits AS W1
INNER JOIN Waits AS W2
ON W2.RowNum <= W1.RowNum
GROUP BY W1.RowNum
HAVING SUM (W2.Percentage) - MAX (W1.Percentage) < 99; -- percentage threshold

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

-- Get CPU trend for pass 256 min 
declare @ts_now bigint
select @ts_now = cpu_ticks / (cpu_ticks/ms_ticks) from sys.dm_os_sys_info;  
select TOP(15) 'CPU_Trend for pass 256 min' as [Category],record_id,
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
order by record_id desc;


/************** Memory ************************************************************************************************************************/
-- This query returns information about the state of the system (totals and available numbers) 
-- as well as the global state if the system detects low, high, or steady memory conditions. 
-- The "Available physical memory is low" indicator in the system_memory_state_desc column is 
-- another sign of external memory pressure that requires further investigation. 
-- Relieving external memory pressure by identifying and eliminating major physical memory 
-- consumers (if possible) and/or by adding more memory should generally resolve problems related to memory.
select 'Memory' as [Category], total_physical_memory_kb / 1048576 as phys_mem_gb,
	   available_physical_memory_kb / 1048576 as avail_phys_mem_gb,
	   system_cache_kb /1048576 as sys_cache_gb,
	   (kernel_paged_pool_kb+kernel_nonpaged_pool_kb) / 1048576 
		as kernel_pool_gb,
	total_page_file_kb / 1048576 as total_page_file_gb,
	available_page_file_kb / 1048576 as available_page_file_gb,
	system_memory_state_desc
from sys.dm_os_sys_memory WITH (NOLOCK); 

-- SQL Server Process Address space info 
-- (shows whether locked pages is enabled, among other things)
-- You want to see 0 for process_physical_memory_low
-- You want to see 0 for process_virtual_memory_low
SELECT 'Memory' as [Category],physical_memory_in_use_kb,locked_page_allocations_kb, 
       page_fault_count, memory_utilization_percentage, 
       available_commit_limit_kb, process_physical_memory_low, 
       process_virtual_memory_low
FROM sys.dm_os_process_memory WITH (NOLOCK);

SELECT N'Memory' as [Category], [object_name],counter_name, cntr_value, N'If Total < Target, SQL cannot grow the buffer pool due to memonry pressure. Total indicates the current size of the buffer poolFurther investigation is required.' AS [description]
FROM sys.dm_os_performance_counters WITH (NOLOCK)
WHERE [object_name] LIKE N'%Memory Manager%' AND counter_name LIKE N'Total Server Memory (KB)%'
UNION
SELECT N'Memory' as [Category], [object_name],counter_name, cntr_value, N'TSM indicates the ideal size for the buffer pool. Total and Traget should be the same' AS [description]
FROM sys.dm_os_performance_counters WITH (NOLOCK)
WHERE [object_name] LIKE N'%Memory Manager%' AND counter_name LIKE N'Target Server Memory (KB)%'
UNION
SELECT N'Memory' as [Category], [object_name],counter_name, cntr_value, N'Higher PLE is better. Watch the trend, not the absolute value' AS [description]
FROM sys.dm_os_performance_counters WITH (NOLOCK)
WHERE [object_name] LIKE N'%Buffer Manager%' AND counter_name = N'Page life expectancy'
UNION
SELECT N'Memory' as [Category], [object_name],counter_name, cntr_value, N'MGO > 0 for a sustained period is a very strong indicator of memory pressure' AS [description]
FROM sys.dm_os_performance_counters WITH (NOLOCK)
WHERE [object_name] LIKE N'%Memory Manager%' AND counter_name = N'Memory Grants Outstanding'
UNION
SELECT N'Memory' as [Category], [object_name],counter_name, cntr_value, N'MGP > 0 for a sustained period is a very strong indicator of memory pressure' AS [description]
FROM sys.dm_os_performance_counters WITH (NOLOCK)
WHERE [object_name] LIKE N'%Memory Manager%' AND counter_name = N'Memory Grants Pending' 


/************** IN-MEMORY ************************************************************************************************************************/
IF @check_in_memory = 1
	BEGIN
	IF (SELECT @@microsoftversion / 0x01000000) > 11 -- greater than SQL 2012
	BEGIN
		IF (SELECT SERVERPROPERTY('IsXTPSupported')) = 1 -- in-memory OLTP is supported
			BEGIN
				DECLARE @varDbName SYSNAME, @dbContext NVARCHAR(500), @sql_str NVARCHAR(4000), @ParmDefinition1 NVARCHAR(500), @pDbXTPIsTrue BIT, @DbXTPIsTrue BIT;

				-- Resource Pool utilization			
				SET @sql_str = N'SELECT pool_id, Name, min_memory_percent, max_memory_percent, max_memory_kb/1024 AS max_memory_mb, 
									used_memory_kb/1024 AS used_memory_mb, target_memory_kb/1024 AS target_memory_mb FROM sys.dm_resource_governor_resource_pools';
				EXECUTE sp_executesql @sql_str

				DECLARE curDbName CURSOR FAST_FORWARD FOR SELECT name FROM sys.databases WHERE database_id > 4;
				OPEN curDbName;
				FETCH NEXT FROM curDbName INTO @varDbName;
				WHILE @@FETCH_STATUS = 0
					BEGIN
						SET @dbContext = @varDbName + N'..' + N'sp_executesql';
						SET @ParmDefinition1 = N'@pDbXTPIsTrue BIT OUTPUT';
						SET @sql_str = N'IF EXISTS (select 1 from sys.data_spaces where type = ''FX'') 
										BEGIN SET @pDbXTPIsTrue = 1 END ELSE BEGIN SET @pDbXTPIsTrue = 0 END';

						EXECUTE @dbContext @sql_str, @ParmDefinition1, @pDbXTPIsTrue = @DbXTPIsTrue OUTPUT;

						IF @DbXTPIsTrue = 1
						BEGIN
							SET @sql_str = N'-- In memory table utilization
											SELECT object_name(object_id) AS table_name, memory_allocated_for_table_kb/1024 memory_allocated_for_table_mb,
											memory_used_by_table_kb/1024 memory_used_by_table_mb, memory_allocated_for_indexes_kb/1024 memory_allocated_for_indexes_mb,
											memory_used_by_indexes_kb/1024 memory_used_by_indexes_mb FROM sys.dm_db_xtp_table_memory_stats (NOLOCK);

											-- XTP usage (Same as XTP Memory Used in PERFMOM, counts Log pool utilization as well)
											Select getdate() as DateTimeCaptured,sum(allocated_Bytes/(1024*1024)) As Total_XTP_Allocated_MB,
											sum(Used_bytes/(1024*1024)) As Total_XTP_Used_MB,
											(sum(allocated_Bytes/(1024*1024)) - sum(Used_bytes/(1024*1024))) As Free_XTP_Memory_MB
											from sys.dm_db_xtp_memory_consumers (NOLOCK);';
							EXECUTE @dbContext @sql_str
						END;
						FETCH NEXT FROM curDbName INTO @varDbName;
					END; -- cursor
				CLOSE curDbName;
				DEALLOCATE curDbName;
			END; -- in-memory OLTP is supported
	END; -- greater than SQL 2012
END; -- @check_in_memory


/************** DISK ************************************************************************************************************************/
-- LUNS information
SELECT DISTINCT 'Disk_Space' AS [Category],vs.volume_mount_point, vs.file_system_type, 
vs.logical_volume_name, CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0) AS [Total Size (GB)],
CONVERT(DECIMAL(18,2),vs.available_bytes/1073741824.0) AS [Available Size (GB)],  
CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,2)) * 100 AS [Space Free %] 
FROM sys.master_files AS f WITH (NOLOCK)
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs;

SELECT 'Data files in drive D' AS [Category], d.name as db_name, CAST((((size)/128.0)/1024) AS INT) as 'size in GB', physical_name
FROM sys.master_files mf
JOIN sys.databases d
ON mf.database_id = d.database_id
where physical_name like 'D%'
and d.name not in ('master','model','msdb','Dell_Maint')
order by d.name;

SELECT 'Database size' AS [Category], d.name as [db_name], CAST((sum(((size)/128.0))/1024) AS INT) as [size in GB]
FROM sys.master_files mf
JOIN sys.databases d
ON mf.database_id = d.database_id
WHERE d.name not in ('master','model','msdb','Dell_Maint')
GROUP BY d.name;


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
    AND num_of_writes > 0;

SELECT 'Tempdb_Usage' as [Category], SUM(user_object_reserved_page_count) AS user_object_pages,
        SUM(internal_object_reserved_page_count) AS internal_object_pages,
        SUM(version_store_reserved_page_count) AS version_store_pages,
        total_in_use_pages = SUM(user_object_reserved_page_count)
        + SUM(internal_object_reserved_page_count)
        + SUM(version_store_reserved_page_count),
        SUM(unallocated_extent_page_count)/(128*1024) AS total_free_space_GB
FROM   tempdb.sys.dm_db_file_space_usage WITH (NOLOCK);

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
		AND dbname NOT IN ('master','model','msdb','tempdb');

DROP TABLE #checkdb;


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
exec xp_readerrorlog 0, 1, N'occurrence(s) of I/O requests taking longer than 15 seconds to complete on file',null,null,null, N'desc';
-- Insufficient memory issues: http://support.microsoft.com/kb/309256 or https://support.microsoft.com/kb/2001221
exec xp_readerrorlog 0, 1, N'A time out occurred while waiting for memory resources to execute the query',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'A There is insufficient system memory to run this query',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'A significant part of sql server memory has been paged out',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'memory',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'HK_E_OUTOFMEMORY',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'SQL Server is terminating because of a system shutdown',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'Always On: The availability replica manager is going offline',null,null,null, N'desc';
exec xp_readerrorlog 0, 1, N'FAIL_PAGE_ALLOCATION',null,null,null, N'desc';

IF @check_missing_indexes = 1
BEGIN 
	SELECT TOP 25
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
	WHERE dm_mid.database_ID > 4
	ORDER BY Database_Name, dm_migs.avg_user_impact DESC;
END;