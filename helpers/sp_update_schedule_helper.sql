DECLARE @schedule_id INT;
DECLARE @start_time TIME = '12:00:00';
DECLARE @sql NVARCHAR(4000);
DECLARE database_curs CURSOR FAST_FORWARD FOR
								SELECT	[schedule].[schedule_id] 
								FROM	 [msdb].[dbo].[sysjobs] AS [jobs] WITh(NOLOCK) 
										 LEFT OUTER JOIN [msdb].[dbo].[sysjobschedules] AS [jobschedule] WITh(NOLOCK) 
												 ON [jobs].[job_id] = [jobschedule].[job_id] 
										 LEFT OUTER JOIN [msdb].[dbo].[sysschedules] AS [schedule] WITh(NOLOCK) 
												 ON [jobschedule].[schedule_id] = [schedule].[schedule_id] 
										 INNER JOIN [msdb].[dbo].[syscategories] [categories] WITh(NOLOCK) 
												 ON [jobs].[category_id] = [categories].[category_id] 
								--WHERE [jobs].[name] like 'UPDATE STATS%';
								WHERE [jobs].[name] like 'DBCC CHECKDB%';
OPEN database_curs;    
FETCH NEXT FROM database_curs INTO @schedule_id
WHILE @@FETCH_STATUS = 0
BEGIN
	-- Backup: Every 1 weeks(s) on Monday, Wednesday, Friday
	-- SET @sql = N'EXEC msdb.dbo.sp_update_schedule @schedule_id=' + CAST(@schedule_id AS nvarchar) + N', @freq_interval=42, @active_start_time = ' +  REPLACE(CONVERT(VARCHAR(8), @start_time, 108),':','');

	-- DBCC CheckDB
	SET @sql = N'EXEC msdb.dbo.sp_update_schedule @schedule_id=' + CAST(@schedule_id AS nvarchar) + N', @freq_interval=1, @active_start_time = ' +  REPLACE(CONVERT(VARCHAR(8), @start_time, 108),':','');
	PRINT @sql;
	EXECUTE sp_executesql @sql;
	FETCH NEXT FROM database_curs INTO @schedule_id
	SELECT @start_time = DATEADD(mi,20,@start_time);
END;
CLOSE database_curs;
DEALLOCATE database_curs;


SELECT 'EXEC msdb.dbo.sp_update_job  @job_name =' + N'''' + [jobs].[name] + N''''+ ' ,@enabled = 1 '
								FROM	 [msdb].[dbo].[sysjobs] AS [jobs] WITh(NOLOCK) 
								WHERE [jobs].[name] like 'UPDATE STATS%'
								or [jobs].[name] like 'DBCC CHECKDB%'