USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'sp_who3')
DROP PROCEDURE sp_who3
GO
CREATE PROCEDURE sp_who3 @type NVARCHAR(128) = NULL, @spid INT = NULL, @database SYSNAME = NULL
AS
/****************************************************************************************** 
   This is a current activity query used to identify what processes are currently running 
   on the processors.  Use to first view the current system load and to identify a session 
   of interest such as blocking, waiting and granted memory.  You should execute the query 
   several times to identify if a query is increasing it's I/O, CPU time or memory granted.
   
   *Revision History
   - 31-Jul-2011 (Rodrigo): Initial development - Extracted from DynamicsPerf
   - 12-Apr-2012 (Rodrigo): Enhanced sql_text, object_name outputs;
								  Added NOLOCK hints and RECOMPILE option;
								  Added BlkBy column;
								  Removed dead-code.
   - 03-Nov-2014 (Rodrigo): Added program_name and open_transaction_count column
   - 10-Nov-2014 (Rodrigo): Added granted_memory_GB
   - 03-Nov-2015 (Rodrigo): Added parameters to show memory and cpu information
   - 12-Nov-2015 (Rodrigo): Added query to get IO info
   - 17-Nov-2015 (Rodrigo): Changed the logic and addedd new parameters
   - 18-Nov-2015 (Rodrigo): Added help content
   - 06-Set-2016 (Rodrigo): Added spid and database parameters
*******************************************************************************************/
BEGIN
	SET NOCOUNT ON;
	DECLARE @sql_who		NVARCHAR(4000);
	DECLARE @sql_memory		NVARCHAR(4000);
	DECLARE @sql_cpu		NVARCHAR(4000);
	DECLARE @sql_count		NVARCHAR(4000);
	DECLARE @sql_idle		NVARCHAR(4000);
	DECLARE @sql_tempdb		NVARCHAR(4000);
	DECLARE @sql_block		NVARCHAR(4000);
	DECLARE @text			NVARCHAR(4000);
	DECLARE @NewLineChar	AS CHAR(2) = CHAR(13) + CHAR(10);
	DECLARE @ParmDefinition NVARCHAR(500);
	DECLARE @pSPID			INT;
	DECLARE @pDatabase		SYSNAME;
	
	SET @sql_who = N'SELECT r.session_id, se.host_name, se.login_name, Db_name(r.database_id) AS dbname, r.status, r.command,
					CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar) + '' hour(s), ''
					+ CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar) + ''min, ''
					+ CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar) + '' sec'' as running_time,
					r.blocking_session_id AS BlkBy, r.open_transaction_count AS NoOfOpenTran, r.wait_type,
					CAST(ROUND((r.granted_query_memory / 128.0)  / 1024,2) AS NUMERIC(10,2))AS granted_memory_GB,
					object_name = OBJECT_SCHEMA_NAME(s.objectid,s.dbid) + ''.'' + OBJECT_NAME(s.objectid, s.dbid),
 					program_name = se.program_name, p.query_plan AS query_plan,
					sql_text = SUBSTRING	(s.text,r.statement_start_offset/2,
						(CASE WHEN r.statement_end_offset = -1 THEN LEN(CONVERT(nvarchar(MAX), s.text)) * 2
							ELSE r.statement_end_offset	END - r.statement_start_offset)/2),
					r.cpu_time,	start_time, percent_complete,		
					CAST((estimated_completion_time/3600000) as varchar) + '' hour(s), ''
					+ CAST((estimated_completion_time %3600000)/60000 as varchar) + ''min, ''
					+ CAST((estimated_completion_time %60000)/1000 as varchar) + '' sec'' as est_time_to_go,
					dateadd(second,estimated_completion_time/1000, getdate()) as est_completion_time
			FROM   sys.dm_exec_requests r WITH (NOLOCK) 
			JOIN sys.dm_exec_sessions se WITH (NOLOCK)
				ON r.session_id = se.session_id 
			OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) s 
			OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) p ';
	-- who is consuming the memory
	SET @sql_memory = N'SELECT session_id, granted_memory_kb FROM sys.dm_exec_query_memory_grants WITH (NOLOCK) ORDER BY 1 DESC;';
	-- who has cached plans that consumed the most cumulative CPU (top 10)
	SET @sql_cpu = N'SELECT TOP 10 DatabaseName = DB_Name(t.dbid), sql_text = SUBSTRING (t.text, qs.statement_start_offset/2,(CASE WHEN qs.statement_end_offset = -1 THEN LEN(CONVERT(nvarchar(MAX), t.text)) * 2 ELSE qs.statement_end_offset END - qs.statement_start_offset)/2),	ObjectName = OBJECT_SCHEMA_NAME(t.objectid,t.dbid) + ''.'' + OBJECT_NAME(t.objectid, t.dbid),qs.execution_count AS [Executions], qs.total_worker_time AS [Total CPU Time],
							qs.total_physical_reads AS [Disk Reads (worst reads)],	qs.total_elapsed_time AS [Duration], qs.total_worker_time/qs.execution_count AS [Avg CPU Time],qs.plan_generation_num, qs.creation_time AS [Data Cached], qp.query_plan	FROM sys.dm_exec_query_stats qs WITH(NOLOCK) CROSS APPLY sys.dm_exec_sql_text(plan_handle) AS t	CROSS APPLY sys.dm_exec_query_plan(plan_handle) AS qp ORDER BY DatabaseName, qs.total_worker_time DESC;';
	-- who is connected and how many sessions it has 		
	SET @sql_count = N'SELECT login_name, [program_name],No_of_Connections = COUNT(session_id) FROM sys.dm_exec_sessions WITH (NOLOCK) WHERE session_id > 50 GROUP BY login_name, [program_name] ORDER BY COUNT(session_id) DESC;';
	-- who is idle that have open transactions
	SET @sql_idle = N'SELECT s.session_id, login_name, login_time, host_name, host_process_id, status FROM sys.dm_exec_sessions AS s WITH (NOLOCK) WHERE EXISTS (SELECT * FROM sys.dm_tran_session_transactions AS t WHERE t.session_id = s.session_id)	AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests AS r WHERE r.session_id = s.session_id)';
	-- who is running tasks that use tempdb (top 5)
	SET @sql_tempdb = N'SELECT TOP 5 session_id, request_id,  user_objects_alloc_page_count + internal_objects_alloc_page_count as task_alloc FROM tempdb.sys.dm_db_task_space_usage  WITH (NOLOCK)	WHERE session_id > 50 ORDER BY user_objects_alloc_page_count + internal_objects_alloc_page_count DESC';
	-- who is blocking
	SET @sql_block = N'SELECT DB_NAME(lok.resource_database_id) as db_name,lok.resource_description,lok.request_type,lok.request_status,lok.request_owner_type,wat.session_id as wait_session_id,wat.wait_duration_ms,wat.wait_type,wat.blocking_session_id	FROM  sys.dm_tran_locks lok WITH (NOLOCK) JOIN sys.dm_os_waiting_tasks wat WITH (NOLOCK) ON lok.lock_owner_address = wat.resource_address';
	-- help
	SET @text = N'Synopsis:' + @NewLineChar +
				N'Who is currently running on my system?'  + @NewLineChar +
				N'-------------------------------------------------------------------------------------------------------------------------------------'  + @NewLineChar +
				N'Description:'  + @NewLineChar +
				N'The first area to look at on a system running SQL Server is the utilization of hardware resources, the core of which are memory,' + @NewLineChar +
				N'storage, CPU and long blockings. Use sp_who3 to first view the current system load and to identify a session of interest.' + @NewLineChar +
				N'You should execute the query several times to identify which session id is most consuming teh system resources.' + @NewLineChar +
				N'-------------------------------------------------------------------------------------------------------------------------------------' + @NewLineChar +
				N'Parameters:'  + @NewLineChar +
				N'sp_who3 null			- who is active;' + @NewLineChar +
				N'sp_who3 ''memory''  	- who is consuming the memory;' + @NewLineChar +
				N'sp_who3 ''cpu''  		- who has cached plans that consumed the most cumulative CPU (top 10);'+ @NewLineChar +
				N'sp_who3 ''count''  	- who is connected and how many sessions it has;'+ @NewLineChar +
				N'sp_who3 ''idle'' 		- who is idle that has open transactions;'+ @NewLineChar +
				N'sp_who3 ''tempdb'' 	- who is running tasks that use tempdb (top 5); and,'+ @NewLineChar +
				N'sp_who3 ''block'' 	- who is blocking.'

	IF @type IS NULL
		BEGIN

			IF (@spid IS NOT NULL) AND (@database IS NOT NULL)
				BEGIN
					SET @sql_who = @sql_who + N'WHERE r.session_id = @pSPID AND db_name(r.database_id) = @pDatabase;';
					SET @ParmDefinition = N'@pSPID INT, @pDatabase SYSNAME';
					EXECUTE sp_executesql @sql_who, @ParmDefinition, @pSPID = @spid, @pDatabase = @Database;
				END;
			ELSE IF @spid IS NOT NULL
				BEGIN
					SET @sql_who = @sql_who + N'WHERE r.session_id = @pSPID;';
					SET @ParmDefinition = N'@pSPID INT';
					EXECUTE sp_executesql @sql_who, @ParmDefinition, @pSPID = @spid;
				END;
			ELSE IF @database IS NOT NULL
				BEGIN
					SET @sql_who = @sql_who + N'WHERE r.session_id <> @@SPID AND se.is_user_process = 1 AND db_name(r.database_id) = @pDatabase;'
					SET @ParmDefinition = N'@pDatabase SYSNAME';
					EXECUTE sp_executesql @sql_who, @ParmDefinition, @pDatabase = @Database;
				END;
			ELSE
				BEGIN
					SET @sql_who = @sql_who + N'WHERE r.session_id <> @@SPID AND se.is_user_process = 1;';
					EXECUTE sp_executesql @sql_who;
				END;
		END
	ELSE IF @type = 'memory'
		EXECUTE sp_executesql @sql_memory;
	ELSE IF @type = 'cpu'
		EXECUTE sp_executesql @sql_cpu;
	ELSE IF @type = 'count'
		EXECUTE sp_executesql @sql_count;
	ELSE IF @type = 'idle'
		EXECUTE sp_executesql @sql_idle;
	ELSE IF @type = 'tempdb'
		EXECUTE sp_executesql @sql_tempdb;
	ELSE IF @type = 'block'
		EXECUTE sp_executesql @sql_block;
	ELSE
		PRINT @text;
END;
GO
