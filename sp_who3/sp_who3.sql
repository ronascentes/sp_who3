USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'sp_who3')
DROP PROCEDURE sp_who3
GO
CREATE PROCEDURE sp_who3 @spid INT = NULL, @database SYSNAME = NULL
AS
/***************************************************************************************************** 
Use sp_who3 to first view the current system load and to identify a session, users, sessions and/or 
processes in an instance of the SQL Server by using the latest DMVs and T-SQL features.
   
Create by @ronascentes Date: 31-Jul-2011
https://github.com/ronascentes/sql-tools/edit/master/sp_who3

*******************************************************************************************/
BEGIN
	SET NOCOUNT ON;
	DECLARE @sql_who		NVARCHAR(4000);
	DECLARE @NewLineChar	AS CHAR(2) = CHAR(13) + CHAR(10);
	DECLARE @ParmDefinition NVARCHAR(500);
	DECLARE @pSPID			INT;
	DECLARE @pDatabase		SYSNAME;
	
	SET @sql_who = N'SELECT r.session_id, se.host_name, se.login_name, Db_name(r.database_id) AS dbname, r.status, r.command,
					CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar) + '' hour(s), ''
					+ CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar) + ''min, ''
					+ CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar) + '' sec'' as running_time,
					r.blocking_session_id AS BlkBy, r.open_transaction_count AS NoOfOpenTran, r.wait_type,
					object_name = OBJECT_SCHEMA_NAME(s.objectid,s.dbid) + ''.'' + OBJECT_NAME(s.objectid, s.dbid),
 					program_name = se.program_name, p.query_plan AS query_plan,
					sql_text = SUBSTRING(s.text,
						(CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END),
						(CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(s.text) ELSE r.statement_end_offset/2 END - (CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END))),
					mg.requested_memory_kb,	mg.granted_memory_kb, mg.ideal_memory_kb, mg.query_cost,
					((((ssu.user_objects_alloc_page_count + (SELECT SUM(tsu.user_objects_alloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)) -
					(ssu.user_objects_dealloc_page_count + (SELECT SUM(tsu.user_objects_dealloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)))*8)/1024) AS user_obj_in_tempdb_MB,
					((((ssu.internal_objects_alloc_page_count + (SELECT SUM(tsu.internal_objects_alloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)) -
					(ssu.internal_objects_dealloc_page_count + (SELECT SUM(tsu.internal_objects_dealloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)))*8)/1024) AS internal_obj_in_tempdb_MB,
					r.cpu_time,	start_time, percent_complete,		
					CAST((estimated_completion_time/3600000) as varchar) + '' hour(s), ''
					+ CAST((estimated_completion_time %3600000)/60000 as varchar) + ''min, ''
					+ CAST((estimated_completion_time %60000)/1000 as varchar) + '' sec'' as est_time_to_go,
					dateadd(second,estimated_completion_time/1000, getdate()) as est_completion_time
			FROM   sys.dm_exec_requests r WITH (NOLOCK)  
			JOIN sys.dm_exec_sessions se WITH (NOLOCK) ON r.session_id = se.session_id
			LEFT OUTER JOIN sys.dm_exec_query_memory_grants mg WITH (NOLOCK) ON r.session_id = mg.session_id AND r.request_id = mg.request_id
			LEFT OUTER JOIN sys.dm_db_session_space_usage ssu WITH (NOLOCK) ON r.session_id = ssu.session_id 
			OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) s 
			OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) p ';

	IF (@spid IS NOT NULL) AND (@database IS NOT NULL)
		BEGIN
			SET @sql_who = @sql_who + N'WHERE r.session_id = @pSPID AND db_name(r.database_id) = @pDatabase;';
			SET @ParmDefinition = N'@pSPID INT, @pDatabase SYSNAME';
			EXECUTE sp_executesql @sql_who, @ParmDefinition, @pSPID = @spid, @pDatabase = @database;
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
			EXECUTE sp_executesql @sql_who, @ParmDefinition, @pDatabase = @database;
		END;
	ELSE
		BEGIN
			SET @sql_who = @sql_who + N'WHERE r.session_id <> @@SPID AND se.is_user_process = 1;';
			EXECUTE sp_executesql @sql_who;
		END;
END;
GO
