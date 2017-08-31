-- like sp_spaceused but much better
SELECT SUM((size/128.0))/1024 AS [Total Size in GB],
SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0)/1024 AS [Space Used in GB],
SUM(size/128.0 - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0)/1024 AS [Available Space in GB],
sum((((size)/128.0) - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0)) / sum(((size)/128.0)) * 100  as '% Available'
FROM sys.database_files WITH (NOLOCK) 
--WHERE type = 1 -- log

-- Volume info for all LUNS that have database files on the current instance
SELECT DISTINCT vs.volume_mount_point, vs.file_system_type, 
vs.logical_volume_name, CONVERT(DECIMAL(18,2),vs.total_bytes/1073741824.0) AS [Total Size (GB)],
CONVERT(DECIMAL(18,2),vs.available_bytes/1073741824.0) AS [Available Size (GB)],  
CAST(CAST(vs.available_bytes AS FLOAT)/ CAST(vs.total_bytes AS FLOAT) AS DECIMAL(18,2)) * 100 AS [Space Free %] 
FROM sys.master_files AS f WITH (NOLOCK)
CROSS APPLY sys.dm_os_volume_stats(f.database_id, f.[file_id]) AS vs 

-- list by data file
SELECT name, physical_name,
(size/128.0)/1024 AS [Total Size in GB],
CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0/1024 AS [Space Used in GB],
size/128.0 - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0/1024 AS [Available Space in GB],
(((size)/128.0) - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0) / ((size)/128.0) * 100  as '% Available'
FROM sys.database_files WITH (NOLOCK)

-- group by type
SELECT SUM((size/128.0))/1024 AS [Total Size in GB],
SUM(CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0)/1024 AS [Space Used in GB],
SUM(size/128.0 - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0)/1024 AS [Available Space in GB],
sum((((size)/128.0) - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)/128.0)) / sum(((size)/128.0)) * 100  as '% Available', type
FROM sys.database_files WITH (NOLOCK) 
GROUP BY type OPTION (RECOMPILE);

-- get space for the datafile
SELECT SUM(((size)/128.0)) AS 'size in MB', SUM(((size)/128.0) - CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT)/128.0) AS AvailableSpaceInMB
     , SUM((((size)/128.0) - CAST(FILEPROPERTY(name, 'SpaceUsed') AS INT)/128.0)) / sum(((size)/128.0)) * 100  AS '% Available'
      ,g.groupname
FROM sysfiles f, sysfilegroups g
WHERE f.groupid = g.groupid
GROUP BY g.groupname;

-- get total space of all databases
SELECT name, sum(((size)/128.0)) as 'size in MB', CAST((sum(((size)/128.0))/1024) AS INT) as 'size in GB'
FROM sys.master_files

SELECT name, CAST((((size)/128.0)/1024) AS INT) as 'size in GB',physical_name
FROM sys.master_files

SELECT d.name as db_name, CAST((((size)/128.0)/1024) AS INT) as 'size in GB', physical_name
FROM sys.master_files mf
JOIN sys.databases d
ON mf.database_id = d.database_id
where physical_name like 'D%'
and d.name not in ('master','model','msdb','Dell_Maint')
order by d.name