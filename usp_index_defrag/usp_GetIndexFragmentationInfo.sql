USE [Dell_Maint]
GO

/****** Object:  StoredProcedure [dbo].[get_index_fragmentation_info]    Script Date: 7/23/2018 1:25:52 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[usp_GetIndexFragmentationInfo]
@DatabaseName sysname
AS

/********************************************************************************************
Description:			Uses sys.dm_db_index_physical_stats to get fragmentation info;
						 
Witten By:				Rodrigo Silva
			
Date:					Jul. 23th, 2018 

Parameters:				@DatabaseName SYSNAME 

Usage:					EXEC get_index_fragmentation_info '<database_name>'

References:				https://blogs.technet.microsoft.com/josebda/2009/03/20/sql-server-2008-fragmentation/
						https://technet.microsoft.com/en-us/library/ms189858(v=sql.110).aspx
						https://blogs.msdn.microsoft.com/alwaysonpro/2015/03/03/recommendations-for-index-maintenance-with-alwayson-availability-groups/
						https://msdn.microsoft.com/en-us/library/ms190981(v=sql.110).aspx

*********************************************************************************************/

DECLARE @SQL NVARCHAR(4000), @dbContext NVARCHAR(500), @sqlversion INT

SET NOCOUNT ON
SET @sqlversion =  @@microsoftversion / 0x01000000;

-- come on dude! that is for SQL Server 2008 or higher
IF  @sqlversion  <= 9
	THROW 50001, 'Index_maint aborted. SQL Server version not supported',1;

-- Check if the database exists and if it is online
IF EXISTS (SELECT CASE WHEN DATABASEPROPERTYEX(name, 'Status') = 'ONLINE' THEN 1 END FROM master.dbo.sysdatabases WHERE name = @DatabaseName)
	SET @dbContext = @DatabaseName + N'..' + N'sp_executesql';
ELSE
	THROW 50001, 'Index_maint aborted. Database name is invalid or database is unavailable',1;

IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = N'index_fragmentation_info')
	CREATE TABLE index_fragmentation_info(
		[DatabaseName] [sysname],
		[ObjectOwner] [sysname] NOT NULL,
		[ObjectName] [sysname] NOT NULL,
		[ObjectID] INT NULL,
		[IndexName] [sysname] NOT NULL,
		[IndexType] TINYINT NOT NULL,
		[LogicalFrag] [decimal](18, 0) NULL,
		[IndexTypeDesc] NVARCHAR(60),
		[AllocUnitTypeDesc] NVARCHAR(60),
		[FragInfoID] int identity (1,1) not null,
		[FragInfoDate] date not null,
		[IsDefragCompleted] INT not null
);

-- get index fragmentation info
SET @Sql = N'INSERT INTO dell_maint.dbo.index_fragmentation_info(DatabaseName, ObjectOwner, ObjectName, ObjectID,IndexName, IndexType, LogicalFrag, IndexTypeDesc, AllocUnitTypeDesc, FragInfoDate, IsDefragCompleted)
			SELECT DB_NAME(), s.name, o.name, i.[object_id], i.name, i.type, stats.avg_fragmentation_in_percent, stats.index_type_desc, stats.alloc_unit_type_desc, getdate(), 0
			FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') stats
			JOIN sys.objects o ON o.object_id = stats.object_id
			JOIN sys.schemas s ON s.schema_id = o.schema_id 
			JOIN sys.indexes i ON i.object_id = stats.object_id AND i.index_id = stats.index_id
			WHERE stats.avg_fragmentation_in_percent >= 10.0 
					AND stats.page_count >= 5000 
					AND stats.index_id > 0';

EXECUTE @dbContext @Sql;

-- purge fragmentation info older than 3 months
DELETE FROM Dell_Maint.dbo.index_fragmentation_info WHERE FragInfoDate <= DATEADD(mm, -3, GETDATE())

GO

