--Run the following query to get the TOP 50 cached plans that consumed the most cumulative CPU
-- Reference http://blogs.msdn.com/b/psssql/archive/2013/06/17/high-cpu-troubleshooting-with-dmv-queries.aspx

USE [master]
GO
SET NOCOUNT ON
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SELECT TOP 25 'Top Queries' as [Info],
	[db_name] = DB_NAME(t.dbid),
      [sql text] = SUBSTRING(t.text,
		(CASE WHEN qs.statement_start_offset = 0 THEN 0 ELSE qs.statement_start_offset/2 END),
		(CASE WHEN qs.statement_end_offset = -1 THEN DATALENGTH(t.text) ELSE qs.statement_end_offset/2 END - (CASE WHEN qs.statement_start_offset = 0 THEN 0 ELSE qs.statement_start_offset/2 END))),
	ISNULL(OBJECT_SCHEMA_NAME(t.objectid,t.dbid) + '.' + OBJECT_NAME(t.objectid, t.dbid), 'ad hoc') AS [ObjectName],
	qs.execution_count AS [executions], 
	qs.total_worker_time / 1000 AS [Total CPU Time],
	qs.total_logical_reads AS [reads],
	qs.total_logical_writes AS [writes],
	qs.total_physical_reads AS [Disk Reads (worst reads)],
	qs.total_elapsed_time AS [duration],
	qs.total_used_grant_kb AS [memory grants],				-- SQL 2014 SP2 or higher only
	qs.total_worker_time/qs.execution_count AS [avg_worker_time],
      qs.total_logical_reads/execution_count AS [Avg_Logical_Reads],
      qs.total_used_grant_kb/execution_count AS [avg_memory_grants], 	-- SQL 2014 SP2 or higher only
	qs.plan_generation_num,
	qs.creation_time AS [data cached]
	-- qp.query_plan                                                  -- uncomment if no need to export to excel
FROM sys.dm_exec_query_stats qs WITH(NOLOCK)
CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t
CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp
WHERE t.dbid > 4
ORDER BY [db_name], qs.total_worker_time DESC -- top expensive CPU
-- ORDER BY [db_name], qs.total_elapsed_time DESC -- top duration
-- ORDER BY DatabaseName, [Avg_Logical_Reads] DESC -- top expensive reads IO
-- ORDER BY [db_name], qs.total_used_grant_kb DESC -- top memory (SQL 2014 SP2 or higher only) 
-- AND qs.plan_generation_num > 1 -- recompiles
-- ORDER BY [db_name], qs.plan_generation_num DESC --  plan_generation_num indicates the nbr of times the query has recompiled
GO

--The following query gives you a high-level view of which currently cached batches or procedures are using the most CPU
SELECT TOP 50 
      SUM(qs.total_worker_time) AS total_cpu_time, 
      SUM(qs.execution_count) AS total_execution_count,
      COUNT(*) AS  number_of_statements, 
      qs.sql_handle 
FROM sys.dm_exec_query_stats AS qs
GROUP BY qs.sql_handle
ORDER BY SUM(qs.total_worker_time) DESC


--The following shows DMV queries to find out excessive compiles/recompiles.
select * from sys.dm_exec_query_optimizer_info
where counter = 'optimizations' or counter = 'elapsed time'


-- An inefficient query plan may cause increased CPU consumption.
-- The following query shows which query is using the most cumulative CPU.
SELECT 
    highest_cpu_queries.plan_handle, 
    highest_cpu_queries.total_worker_time,
    q.dbid,
    q.objectid,
    q.number,
    q.encrypted,
    q.[text]
from 
    (select top 50 
        qs.plan_handle, 
        qs.total_worker_time
    from 
        sys.dm_exec_query_stats qs
    order by qs.total_worker_time desc) as highest_cpu_queries
    cross apply sys.dm_exec_sql_text(plan_handle) as q
order by highest_cpu_queries.total_worker_time desc


-- The following query shows some operators that may be CPU intensive, such as ‘%Hash Match%’, ‘%Sort%’ to look for suspects.
-- If you have detected inefficient query plans and that cause high CPU consumption, run UPDATE STATISTICS on the tables involved in the query and check to see if the problem persists. 
select *
from 
      sys.dm_exec_cached_plans
      cross apply sys.dm_exec_query_plan(plan_handle)
where 
      cast(query_plan as nvarchar(max)) like '%Sort%'
      or cast(query_plan as nvarchar(max)) like '%Hash Match%'
      

-- Get CPU utilization by database (adapted from Robert Pearl)
-- Helps determine which database is using the most CPU resources on the instance
WITH DB_CPU_Stats
AS
(SELECT DatabaseID, DB_Name(DatabaseID) AS [DatabaseName], SUM(total_worker_time) AS [CPU_Time_Ms]
 FROM sys.dm_exec_query_stats AS qs
 CROSS APPLY (SELECT CONVERT(int, value) AS [DatabaseID] 
              FROM sys.dm_exec_plan_attributes(qs.plan_handle)
              WHERE attribute = N'dbid') AS F_DB
 GROUP BY DatabaseID)
SELECT ROW_NUMBER() OVER(ORDER BY [CPU_Time_Ms] DESC) AS [row_num],
       DatabaseName, [CPU_Time_Ms], 
       CAST([CPU_Time_Ms] * 1.0 / SUM([CPU_Time_Ms]) OVER() * 100.0 AS DECIMAL(5, 2)) AS [CPUPercent]
FROM DB_CPU_Stats
WHERE DatabaseID > 4 -- system databases
AND DatabaseID <> 32767 -- ResourceDB
ORDER BY row_num OPTION (RECOMPILE);



-- Get CPU trend for pass 256 min
declare @ts_now bigint
select @ts_now = cpu_ticks / (cpu_ticks/ms_ticks) from sys.dm_os_sys_info;  
select TOP(10) record_id,
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
