USE [master]
GO

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND OBJECT_ID = OBJECT_ID('dbo.sp_who3'))
	DROP PROCEDURE [dbo].[sp_who3]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE  PROCEDURE [dbo].[sp_who3]
@filter SYSNAME = NULL,
@info SYSNAME = NULL,
@orderby SYSNAME = NULL
AS

/***************************************************************************************************** 
sp_who3 v1.1.0

Use sp_who3 to first view the current system load and to identify a session, users and/or requests of interest.

Source: https://github.com/ronascentes/sp_who3

MIT License

Copyright (c) 2021 Rodrigo Nascentes

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*****************************************************************************************************/

BEGIN
	SET NOCOUNT, XACT_ABORT ON;
	DECLARE @sqlStmt NVARCHAR(4000), @ParmDefinition NVARCHAR(25) = N'@pFilter SYSNAME', @pFilter SYSNAME, @ParmFlag BIT = 0, @MajorVersion INT;
	SELECT @MajorVersion = CONVERT(int, (@@microsoftversion / 0x1000000));
	
	IF (@MajorVersion < 11)
		THROW 50001, N'SQL Server version not supported. Please use SQL Server 2012 or higher.', 1;
	
	IF (@info IS NOT NULL) AND (UPPER(@info) NOT IN (N'IDLE', N'COUNT', N'SLEEPING'))
				THROW 50001, N'Invalid parameter value for @info. Please use ''IDLE'', ''COUNT'' or ''SLEEPING''. Default value is null.', 1;

	IF (@orderby IS NOT NULL) AND (UPPER(@orderby) NOT IN (N'CPU', N'DURATION'))
				THROW 50001, N'Invalid parameter value for @orderby. Please use ''CPU'' for cpu_time or ''DURATION'' for running_time. Default value is null.', 1;

	IF (UPPER(@info) IS NULL) -- who is currently active
	BEGIN
		SET @sqlStmt = N'SELECT r.session_id, se.host_name, se.login_name, db_name(r.database_id) AS db_name, r.status, r.command,
							CAST(((DATEDIFF(s,start_time,GetDate()))/3600) as varchar) + '' hour(s), ''
							+ CAST((DATEDIFF(s,start_time,GetDate())%3600)/60 as varchar) + ''min, ''
							+ CAST((DATEDIFF(s,start_time,GetDate())%60) as varchar) + '' sec'' as running_time, r.cpu_time,
							r.blocking_session_id AS blk_by, r.open_transaction_count AS open_tran_count, r.wait_type, r.wait_resource,';

		IF (@MajorVersion >= 15)
			SET @sqlStmt += N' pi.page_type_desc,';

		SET @sqlStmt += N' object_name = OBJECT_SCHEMA_NAME(s.objectid,s.dbid) + ''.'' + OBJECT_NAME(s.objectid, s.dbid),
						program_name = se.program_name, p.query_plan AS query_plan,
						sql_text = SUBSTRING(s.text,
							1+(CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END),
							1+(CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(s.text) ELSE r.statement_end_offset/2 END - (CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END))),
						r.sql_handle, mg.requested_memory_kb, mg.granted_memory_kb, mg.ideal_memory_kb, mg.query_cost,
						((((ssu.user_objects_alloc_page_count + (SELECT SUM(tsu.user_objects_alloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)) -
						(ssu.user_objects_dealloc_page_count + (SELECT SUM(tsu.user_objects_dealloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)))*8)/1024) AS user_obj_in_tempdb_MB,
						((((ssu.internal_objects_alloc_page_count + (SELECT SUM(tsu.internal_objects_alloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)) -
						(ssu.internal_objects_dealloc_page_count + (SELECT SUM(tsu.internal_objects_dealloc_page_count) FROM sys.dm_db_task_space_usage tsu WHERE tsu.session_id = ssu.session_id)))*8)/1024) AS internal_obj_in_tempdb_MB,
						start_time, percent_complete,		
						CAST((estimated_completion_time/3600000) as varchar) + '' hour(s), ''
						+ CAST((estimated_completion_time %3600000)/60000 as varchar) + ''min, ''
						+ CAST((estimated_completion_time %60000)/1000 as varchar) + '' sec'' as est_time_to_go,
						dateadd(second,estimated_completion_time/1000, getdate()) as est_completion_time
					FROM sys.dm_exec_requests r WITH (NOLOCK)  
					JOIN sys.dm_exec_sessions se WITH (NOLOCK) 
						ON r.session_id = se.session_id
					LEFT OUTER JOIN sys.dm_exec_query_memory_grants mg WITH (NOLOCK) 
						ON r.session_id = mg.session_id AND r.request_id = mg.request_id
					LEFT OUTER JOIN sys.dm_db_session_space_usage ssu WITH (NOLOCK) 
						ON r.session_id = ssu.session_id
					OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) s 
					OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) p';

		IF (@MajorVersion >= 15)
			SET @sqlStmt += N' OUTER APPLY sys.fn_PageResCracker(r.page_resource) pr  
							OUTER APPLY sys.dm_db_page_info(ISNULL(pr.db_id, 0), ISNULL(pr.file_id, 0), ISNULL(pr.page_id, 0), ''LIMITED'') pi';
			
		IF (@filter IS NULL)
			SET @sqlStmt += N' WHERE r.session_id <> @@SPID AND se.is_user_process = 1';
		ELSE
		BEGIN
			IF (PATINDEX ('%[^0-9]%' , ISNULL(@filter,'z')) = 0)  -- that's a spid
				SET @sqlStmt += N' WHERE r.session_id = @pFilter';
			ELSE
				SET @sqlStmt += N' WHERE se.login_name = @pFilter';
					
			SET @ParmFlag = 1
		END;

		IF (@orderby IS NOT NULL)
		BEGIN
			IF (UPPER(@orderby) = N'CPU' )
				SET @sqlStmt += N' ORDER BY r.cpu_time DESC';
			ELSE IF (UPPER(@orderby) = N'DURATION')
				SET @sqlStmt += N' ORDER BY running_time DESC';
		END;
	END;
	ELSE IF (UPPER(@info) = 'IDLE') -- who is idle that have open transactions
	BEGIN
		SET @sqlStmt = N'SELECT s.session_id, host_name, login_name, DB_NAME(database_id) AS db_name, program_name, status, 
							(memory_usage/128.0)/1024 as memory_usage_gb,
							CAST(((DATEDIFF(s,login_time,GetDate()))/3600) as varchar) + '' hour(s), ''
									+ CAST((DATEDIFF(s,login_time,GetDate())%3600)/60 as varchar) + ''min, ''
									+ CAST((DATEDIFF(s,login_time,GetDate())%60) as varchar) + '' sec'' as running_time,
							open_transaction_count
						FROM sys.dm_exec_sessions s WITH (NOLOCK) 
						WHERE EXISTS (SELECT * FROM sys.dm_tran_session_transactions t WITH (NOLOCK) WHERE t.session_id = s.session_id) 
						AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests r WITH (NOLOCK) WHERE r.session_id = s.session_id) AND is_user_process = 1';
	END;
	ELSE IF (UPPER(@info) = 'COUNT') -- who is connected and how many sessions it has 
	BEGIN
		SET @sqlStmt = N'SELECT login_name, [program_name], connections_count = COUNT(s.session_id) 
						FROM sys.dm_exec_connections c WITH (NOLOCK)  
						JOIN sys.dm_exec_sessions s WITH (NOLOCK) ON c.session_id = s.session_id';
			
		IF (@filter IS NULL)
			SET @sqlStmt += N' WHERE c.session_id <> @@SPID AND s.is_user_process = 1';	
		ELSE
			BEGIN
				SET @sqlStmt += N' WHERE se.login_name = @pFilter';
				SET @ParmFlag = 1;
			END;
						
		SET @sqlStmt += N' GROUP BY login_name, [program_name] ORDER BY COUNT(s.session_id) DESC';
	END;
	ELSE IF (UPPER(@info) = 'SLEEPING') -- who is sleeping (currently running no requests)
	BEGIN
		SET @sqlStmt = N'SELECT s.session_id, s.host_name, s.login_name, s.program_name, db_name(s.database_id) AS db_name, s.status,
							s.open_transaction_count,
							+ CAST((DATEDIFF(s,c.connect_time,GetDate())%3600)/60 as varchar) + ''min, ''
							+ CAST((DATEDIFF(s,c.connect_time,GetDate())%60) as varchar) + '' sec '' as running_time,
							t.text AS most_recent_sql_handle
						FROM sys.dm_exec_connections c WITH (NOLOCK) 
						JOIN sys.dm_exec_sessions s WITH (NOLOCK) ON c.session_id = s.session_id
						OUTER APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
						WHERE s.is_user_process = 1	AND status = ''sleeping''';
			
		IF (@filter IS NULL)
			SET @sqlStmt += N' AND s.session_id <> @@SPID';
		ELSE
		BEGIN
			IF (patindex ('%[^0-9]%' , isnull(@filter,'z')) = 0)
				SET @sqlStmt += N' AND s.session_id = @pFilter';
			ELSE
				SET @sqlStmt += N' AND s.login_name = @pFilter';
					
			SET @ParmFlag = 1
		END;

		IF (@orderby IS NOT NULL)
		BEGIN
			IF (UPPER(@orderby) = N'DURATION')
				SET @sqlStmt += N' ORDER BY running_time DESC';
		END;
	END;
	
	IF @ParmFlag = 0
		EXECUTE sp_executesql @sqlStmt;
	ELSE
		EXECUTE sp_executesql @sqlStmt, @ParmDefinition, @pFilter = @filter;
			
END;
GO
