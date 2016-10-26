USE [Dell_Maint]
GO

/****** Object:  UserDefinedFunction [dbo].[ufn_GetCpuUsage]    Script Date: 10/18/2016 7:05:00 AM ******/
DROP FUNCTION [dbo].[ufn_GetCpuUsage]
GO

/****** Object:  UserDefinedFunction [dbo].[ufn_GetCpuUsage]    Script Date: 10/18/2016 7:05:00 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[ufn_GetCpuUsage]()
RETURNS decimal   
AS   
BEGIN  
    DECLARE @CPU decimal;
	DECLARE @ts_now BIGINT;  
	SELECT @ts_now = cpu_ticks / (cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info;
	SELECT TOP(1) @CPU = SQLProcessUtilization
	FROM (
		  SELECT
				record.value('(./Record/@id)[1]', 'int') as record_id,
				record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') as SystemIdle,
				record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') as SQLProcessUtilization,
				timestamp
		  FROM (
				SELECT timestamp, convert(xml, record) as record
				FROM sys.dm_os_ring_buffers
				WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
				AND record like '%<SystemHealth>%') as x
		  ) AS y
	ORDER BY record_id DESC; 
    RETURN @CPU;  
END;  


GO


