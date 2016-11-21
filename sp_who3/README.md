
Stop using sp_who2, start using sp_who3!

# sp_who3

Use sp_who3 to first view the current system load and to identify a session, users, sessions and/or processes in an instance of the SQL Server. Sp_who3 was build by using the latest DMVs and T-SQL features.

## Limitation

Work only for SQL Server 2008 R2 or above 

## Parameters

@spid 999           : filter sessions by spid
@database 'db_name' : filter sessions by database name
@type 'memory'      : who is consuming the memory
@type 'cpu'         : who has cached plans that consumed the most cumulative CPU (top 10)
@type 'count'       : who is connected and how many sessions it has
@type 'idle'        : who is idle that have open transactions
@type 'tempdb'      : who is running tasks that use tempdb (top 5)
@type 'block'       : who is blocking

## Reference

sys.dm_exec_requests - https://msdn.microsoft.com/us-us/library/ms177648.aspx

sys.dm_exec_sessions - https://msdn.microsoft.com/en-us/library/ms176013.aspx

sys.dm_exec_sql_text - https://msdn.microsoft.com/en-us/library/ms181929.aspx

sys.dm_exec_text_query_plan - https://msdn.microsoft.com/en-us/library/bb326654.aspx

sys.dm_exec_query_stats - https://msdn.microsoft.com/en-us/library/ms189741.aspx

sys.dm_tran_session_transactions - https://msdn.microsoft.com/en-us/library/ms188739.aspx

sys.dm_db_task_space_usage - https://msdn.microsoft.com/en-us/library/ms190288.aspx

sys.dm_tran_locks - https://msdn.microsoft.com/en-us/library/ms190345.aspx

sys.dm_os_waiting_tasks - https://msdn.microsoft.com/en-us/library/ms188743.aspx

High CPU Troubleshooting with DMV Queries - http://blogs.msdn.com/b/psssql/archive/2013/06/17/high-cpu-troubleshooting-with-dmv-queries.aspx

SQL Server Diagnostic Information Queries - http://sqlserverperformance.wordpress.com/


* If you have further questions, contact: @ronascentes at twitter
