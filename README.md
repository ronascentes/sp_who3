# SP_WHO3

Community version of [sp_who](https://docs.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-who-transact-sql?view=sql-server-ver15) which provides information about current users, sessions, and processes in an instance of the Microsoft SQL Server Database Engine.

- Current active sessions/ requests
- Current idle sessions that have open transactions
- Connected users and how many sessions they have
- Connected sessions that are running no requests (sleeping)

## Why yet another stored procedure similiar of sp_who?

There are other great tools with same purpose such as [sp_blitz](https://www.brentozar.com/blitz/) and [sp_whoisactive](http://whoisactive.com/). Those tools might be more compreensive and complete than sp_who3 for activity monitoring. For example, sp_whoisactive has twenty-four parameters which you choose from a variety of options but sp_who3 has only three.

The motivation behind the sp_who3 development is to have a simple, small and straightforward user experience tool to run faster during a critical war room where every second wasted to restore a service counts. The sp_who3 code can be easily maintained and modified as per user needs. To sum up, sp_who3 follow the [KISS Principle](https://en.wikipedia.org/wiki/KISS_principle) of "Keep it Simple, Stupid". 

## Sintax

``` 
sp_who3 [ [ @filter = ] 'login_name' | SPID ]
[, [ @info = ] 'IDLE' | 'COUNT' | 'SLEEPING' ]
[, [ @orderby = ] 'CPU' | 'DURATION' ]
``` 

## Parameters

`[ @filter = ] 'login_name' | SPID` 

Is used to filter the result set. Default value is null.

*login_name* is **sysname** that identifies processes belonging to a particular login. It has no effect for @info = 'IDLE'

*SPID* is a session identification number belonging to the SQL Server instance. SPID is smallint. It has no effect for @info = 'IDLE' | 'COUNT'.


`[ @info = ] 'IDLE' | 'COUNT' | 'SLEEPING'`

Is used to select the type of information. Default value is null which show information about current users, sessions and requests in an SQL Server instance.

*IDLE* provides information about current idle sessions that have open transactions

*COUNT* provides information about connected users and how many sessions they have

*SLEEPING* provides information about connected sessions that are not running requests


`[ @orderby = ] 'CPU' | 'DURATION'`	

Is used to order the result set by the selected option. Default value is null.

*CPU* provides information from highest to lowest cpu_time value. It has no effect for @info = 'IDLE' | 'COUNT' | 'SLEEPING'.

*DURATION* provides information from highest to lowest running_time value. It has no effect for @info = 'IDLE' | 'COUNT'.


## Result set

| Column | Data Type | Description |
| --- | --- | --- |
| session_id | smallint | ID of the session to which this request is related. Is not nullable. |
| host_name | nvarchar(128) | Name of the client workstation that is specific to a session. The value is NULL for internal sessions. Is nullable. |
| login_name | nvarchar(128) | SQL Server login name under which the session is currently executing. |
| db_name | nvarchar(128) | Name of the database the request is executing against. Is not nullable. |
| status | nvarchar(30)	| Status of the request. |
| command | nvarchar(32) |	Identifies the current type of command that is being processed. |
| running_time| varchar | Period of time that request is running. Is not nullable. |
| blk_by	| smallint | ID of the session that is blocking the request. |
| open_tran_count| int	| Number of transactions that are open for this request. Is not nullable. |
| wait_type	| nvarchar(60) | If the request is currently blocked, this column returns the type of wait. Is nullable. |
| wait_resource | nvarchar(256) | If the request is currently blocked, this column returns the resource for which the request is currently waiting. Isn't nullable. |
| page_type_desc | nvarchar(64) | Description of the page type (only available for SQL Server 2019 or later). |
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

## Limitation

Tested and validated for SQL Server 2012 or above.

## License

sp_who3 (and its repository) is licensed under the [MIT License](https://github.com/ronascentes/sp_who3/blob/master/LICENSE)

## Maintainer

Rodrigo Nascentes - [@ronascentes](https://twitter.com/ronascentes)

## Reference

System Dynamic Management Views - https://docs.microsoft.com/en-us/sql/relational-databases/system-dynamic-management-views/system-dynamic-management-views
 
Microsoft Tiger Team - https://github.com/Microsoft/tigertoolbox

DynamicsPerf - https://blogs.msdn.microsoft.com/axinthefield and https://blogs.msdn.microsoft.com/axperf/



