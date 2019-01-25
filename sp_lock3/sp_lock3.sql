USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'sp_lock3')
DROP PROCEDURE sp_lock3
GO
CREATE PROCEDURE sp_lock3
AS
/***************************************************************************************************** 
Use sp_who3 to first view the current system load and to identify a session, users, sessions and/or 
processes in an instance of the SQL Server by using the latest DMVs and T-SQL features.
   
Create by @ronascentes Date: 31-Jul-2011
https://github.com/ronascentes/sql-tools/edit/master/sp_who3

*******************************************************************************************/
BEGIN
	SET NOCOUNT ON;
    SELECT  r.blocking_session_id,
            dtlbl.request_type AS blocking_request_type,
            destbl.[text] AS blocking_sql,
            DB_NAME(dtl.resource_database_id) AS db_name,
            dtl.request_session_id AS waiting_session_id,  
            dowt.resource_description,
            r.wait_type,
            dowt.wait_duration_ms,
            dtl.resource_associated_entity_id AS waiting_associated_entity,
            dtl.resource_type AS waiting_resource_type,
            dtl.request_type AS waiting_request_type,
            waiting_sql = SUBSTRING(s.text,
                            (CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END),
                            (CASE WHEN r.statement_end_offset = -1 THEN DATALENGTH(s.text) ELSE r.statement_end_offset/2 END - (
                            CASE WHEN r.statement_start_offset = 0 THEN 0 ELSE r.statement_start_offset/2 END)))
    FROM    sys.dm_tran_locks (NOLOCK) AS dtl
    JOIN    sys.dm_os_waiting_tasks (NOLOCK) AS dowt ON dtl.lock_owner_address = dowt.resource_address
    JOIN    sys.dm_exec_requests (NOLOCK) AS r ON r.session_id = dtl.request_session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS s
    LEFT JOIN sys.dm_exec_requests (NOLOCK) derbl ON derbl.session_id = dowt.blocking_session_id
    OUTER APPLY sys.dm_exec_sql_text(derbl.sql_handle) AS destbl
    LEFT JOIN sys.dm_tran_locks (NOLOCK) AS dtlbl  ON derbl.session_id = dtlbl.request_session_id;
END;
GO