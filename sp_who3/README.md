
Stop using sp_who2, start using sp_who3!

# sp_who3

Use sp_who3 to first view the current system load and to identify a session, users, requests, processes and/or blockers in an instance of the SQL Server by using the latest DMVs and T-SQL features.

## Limitation

Works only for SQL Server 2008 R2 or above 

## Parameters

[@spid = 999]           : filter sessions by spid. Default is null.

[@database = 'db_name'] : filter sessions by database name. Default is null.

## Result set

| Column | Data Type | Description |
| --- | --- | --- |
| session_id | smallint | ID of the session to which this request is related. Is not nullable. |
| host_name | nvarchar(128) | Name of the client workstation that is specific to a session. The value is NULL for internal sessions. Is nullable. |
| login_name | nvarchar(128) | SQL Server login name under which the session is currently executing. |
| dbname | nvarchar(128) | Name of the database the request is executing against. Is not nullable. |
| status | nvarchar(30)	| Status of the request. |
| command | nvarchar(32) |	Identifies the current type of command that is being processed. |
| running_time| varchar | Period of time that request is running. Is not nullable. |
| BlkBy	| smallint | ID of the session that is blocking the request. |
| NoOfOpenTran| int	| Number of transactions that are open for this request. Is not nullable. |
| wait_type	| nvarchar(60) | If the request is currently blocked, this column returns the type of wait. Is nullable. |
| object_name | sysname | Name of object. |
| program_name| nvarchar(128) |	Name of client program that initiated the session. The value is NULL for internal sessions. Is nullable.|
| query_plan | xml | Contains the compile-time Showplan representation of the query execution plan that is specified with plan_handle. |
| sql_text | varchar(max) |Retrieve the currently executing statement for the request. Is nullable. |
| sql_handle | varbinary(64) | Hash map of the SQL text of the request. Is nullable. |
| requested_memory_kb | bigint | Total requested amount of memory in kilobytes. |
| granted_memory_kb	| bigint | Total amount of memory actually granted in kilobytes. Can be NULL if the memory is not granted yet. For a typical situation, this value should be the same as requested_memory_kb.|
| ideal_memory_kb | bigint | Size, in kilobytes (KB), of the memory grant to fit everything into physical memory. This is based on the cardinality estimate. |
| query_cost | float | Estimated query cost. |
| user_obj_in_tempdb_MB	| bigint | Space usage for user objects in tempdb by the session.  |
| internal_obj_in_tempdb_MB	| bigint | Space usage for internal objects in tempdb by the session. |
| cpu_time | int | CPU time in milliseconds that is used by the request. Is not nullable. |
| start_time | datetime	| Timestamp when the request arrived. Is not nullable. |
| percent_complete | real | Percentage of work completed for some commands. |
| est_time_to_go | datetime | Estimate complete time of the request. |
| est_completion_time | datetime | Estimate complete datetime of the request. |



## Reference

System Dynamic Management Views - https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/system-dynamic-management-views
 
Microsoft Tiger Team - https://github.com/Microsoft/tigertoolbox

DynamicsPerf - https://blogs.msdn.microsoft.com/axinthefield and 

## Contact 

http://twitter.com/ronascentes

