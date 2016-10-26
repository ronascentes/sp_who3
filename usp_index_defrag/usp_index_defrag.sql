USE [Dell_Maint]
GO

/****** Object:  StoredProcedure [dbo].[usp_index_maint]    Script Date: 7/28/2016 12:09:11 PM ******/
DROP PROCEDURE [dbo].[usp_index_defrag]
GO

/****** Object:  StoredProcedure [dbo].[usp_index_maint]    Script Date: 7/28/2016 12:09:11 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_index_defrag]
@DatabaseName sysname
AS

/********************************************************************************************
usp_index_defrag:		Uses sys.dm_db_index_physical_stats to get fragmentation info;
						Does not rebuild everything every week;
						If fragmentation level <= 30%: reorganize;
						If fragmentation level > 30%: rebuild online or offline;
						Uses MAXDOP to reduce the concurrent index alteration activity;
						Uses the latest ALTER INDEX features
						Works only for SQL Server 2008 or above;
						Rebuilding indexes can cause the log file to grow significantly as the log cannot be truncated until redo has completed the changes in all secondary replicas.
						https://support.microsoft.com/en-us/kb/317375
						 
Witten By:				Rodrigo N Silva 
			
Date:					Jun. 6th, 2016 

Parameters:				@DatabaseName SYSNAME 

Usage:					EXEC usp_index_defrag '<database_name>'

References:				https://blogs.technet.microsoft.com/josebda/2009/03/20/sql-server-2008-fragmentation/
						https://technet.microsoft.com/en-us/library/ms189858(v=sql.110).aspx
						https://blogs.msdn.microsoft.com/alwaysonpro/2015/03/03/recommendations-for-index-maintenance-with-alwayson-availability-groups/
						https://msdn.microsoft.com/en-us/library/ms190981(v=sql.110).aspx
*********************************************************************************************/

DECLARE @SQL NVARCHAR(4000), @ErrorMessage NVARCHAR(4000);
DECLARE @ObjectOwner SYSNAME, @ObjectName SYSNAME,  @pObjectName SYSNAME, @IndexName SYSNAME;
DECLARE @ErrorNum INT, @FragInfoID INT, @sqlversion INT, @ObjectId INT, @RebuildOnlineIsTrue INT, @pObjectID INT, @ErrorSeverity INT, @ErrorState INT;
DECLARE @IndexHasLOB BIT, @pIndexHasLOB BIT, @TableHasLOB1 BIT,@pTableHasLOB1 BIT, @TableHasLOB2 BIT,@pTableHasLOB2 BIT;
DECLARE @percentfrag DECIMAL(38,10), @PercentThreshold DECIMAL(38,10);
DECLARE @IndexTypeDesc NVARCHAR(60), @AllocUnitTypeDesc NVARCHAR(60);
DECLARE @ParmDefinition1 NVARCHAR(500), @ParmDefinition2 NVARCHAR(500),@ParmDefinition3 NVARCHAR(500),@dbContext NVARCHAR(500), @RebuildIndexOnline NVARCHAR(500), @RebuildIndexOffline NVARCHAR(500), @RebuildIndexOnlineforSQL2014 NVARCHAR(500);
DECLARE @DefragStart DATETIME;

SET NOCOUNT ON
SET @sqlversion =  @@microsoftversion / 0x01000000

-- come on dude! that is for SQL Server 2008 or higher
IF  @sqlversion  <= 9
	RAISERROR ('Index_maint aborted. SQL Server version not supported',17,1) WITH LOG

-- Check if the database exists and if it is online
IF EXISTS (SELECT CASE WHEN DATABASEPROPERTYEX(name, 'Status') = 'ONLINE' THEN 1 END FROM master.dbo.sysdatabases WHERE name = @DatabaseName)
	BEGIN
		SET @dbContext = @DatabaseName + N'..' + N'sp_executesql';
		SET @ParmDefinition1 = N'@pObjectID INT, @pIndexHasLOB BIT OUTPUT';
		SET @ParmDefinition2 = N'@pObjectName SYSNAME, @pTableHasLOB1 BIT OUTPUT';
		SET @ParmDefinition3 = N'@pObjectName SYSNAME, @pTableHasLOB2 BIT OUTPUT';  
		SET @PercentThreshold = 30; -- fragmentation threshold percentage.  
		
		SET @RebuildIndexOnline = N' REBUILD WITH (ONLINE = ON, MAXDOP = 1, FILLFACTOR = 80, SORT_IN_TEMPDB = ON, STATISTICS_NORECOMPUTE = OFF)';
		SET @RebuildIndexOffline = N' REBUILD WITH (ONLINE = OFF, MAXDOP = 4, FILLFACTOR = 80, SORT_IN_TEMPDB = ON, STATISTICS_NORECOMPUTE = OFF)';
		-- WAIT_AT_LOW_PRIORITY indicates that the online index rebuild operation will wait for low priority locks, allowing other operations to proceed while the online index build operation is waiting. 
		SET @RebuildIndexOnlineforSQL2014 = N' REBUILD WITH (ONLINE = ON (WAIT_AT_LOW_PRIORITY (MAX_DURATION = 10 MINUTES, ABORT_AFTER_WAIT = BLOCKERS)), MAXDOP = 1, FILLFACTOR = 80, SORT_IN_TEMPDB = ON, STATISTICS_NORECOMPUTE = OFF)';
	END;	
ELSE
	RAISERROR ('Index_maint aborted. Database name is invalid or database is unavailable',17,1) WITH LOG  

IF EXISTS (select * from tempdb..sysobjects where name = '#frag_info')
  DROP TABLE #frag_info

-- Get the list of objects to defrag
CREATE TABLE #frag_info(
	[DatabaseName] [sysname],
	[ObjectOwner] [sysname] NOT NULL,
	[ObjectName] [sysname] NOT NULL,
	[ObjectID] INT NULL,
	[IndexName] [sysname] NOT NULL,
	[LogicalFrag] [decimal](18, 0) NULL,
	[IndexTypeDesc] NVARCHAR(60),
	[AllocUnitTypeDesc] NVARCHAR(60),
	[FragInfoID] int identity (1,1) not null
)

-- get fragmentation info. That's the heart of this stored procedure.
SET @Sql = N'INSERT INTO #frag_info(DatabaseName, ObjectOwner, ObjectName, ObjectID,IndexName, LogicalFrag, IndexTypeDesc, AllocUnitTypeDesc)
			SELECT DB_NAME(), s.name, o.name, i.[object_id], i.name, stats.avg_fragmentation_in_percent, stats.index_type_desc, stats.alloc_unit_type_desc	
			FROM sys.Dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') stats
			JOIN sys.objects o ON o.object_id = stats.object_id
			JOIN sys.schemas s ON s.schema_id = o.schema_id 
			JOIN sys.indexes i ON i.object_id = stats.object_id AND i.index_id = stats.index_id
			WHERE stats.avg_fragmentation_in_percent >= 10.0 
					AND stats.page_count >= 1000 
					AND stats.index_id > 0'

EXECUTE @dbContext @Sql

WHILE EXISTS (SELECT 1 FROM #frag_info)
BEGIN

	idle_while:

	-- check if cpu usage is good to continue
	IF [Dell_Maint].[dbo].[ufn_GetCpuUsage]() > 70
	BEGIN
		WAITFOR DELAY '00:00:30'
		GOTO idle_while
	END
	
	-- get first index to defrag  
	SELECT TOP(1) @ObjectOwner = ObjectOwner, @ObjectName = ObjectName, @ObjectId = ObjectId, @IndexName = IndexName, 
		@percentfrag = LogicalFrag,	@FragInfoID = FragInfoID,@IndexTypeDesc = IndexTypeDesc, @AllocUnitTypeDesc = AllocUnitTypeDesc FROM #frag_info
		ORDER BY ObjectId ;
		
	-- If less than or equal this amount then REORGANIZE the index; If greater than to this amount them REBUILD the Index
	-- ALTER INDEX REORGANIZE statement is always performed online. This means long-term blocking table locks are not held and queries or updates to the underlying table can continue during the ALTER INDEX REORGANIZE transaction. 
	IF @percentfrag <= @PercentThreshold
	BEGIN
		SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + N' REORGANIZE';
		goto exec_defrag;
	END;

	-- If SQL Server 2008 and 2008R2
	IF @sqlversion < 11
	BEGIN
		-- REBUILD WITH ONLINE = ON fails for xml and spatial index. 
		-- And also for LOB_DATA allocation unit (text, ntext, image, varchar(max), nvarchar(max), varbinary(max), and xml) and ROW_OVERFLOW_DATA.
		IF (@IndexTypeDesc IN ('PRIMARY XML INDEX','SPATIAL INDEX','XML INDEX')) OR (@AllocUnitTypeDesc != 'IN_ROW_DATA')
		BEGIN
			-- offline index operation
			SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOffline;
			GOTO exec_defrag;
		END;	
		ELSE IF @IndexTypeDesc = 'NONCLUSTERED INDEX'
		BEGIN
			-- Check if image, text, ntext, xml, varchar, nvarchar, varbinary,char,nchar columns are used in the index definition as either key or nonkey (included) columns
			SET @SQL = N'IF EXISTS (SELECT 1 FROM sys.indexes AS i
										JOIN sys.index_columns AS ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
										JOIN sys.columns AS c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
										AND ((c.system_type_id IN (34,35,99,241)) -- image, text, ntext, xml
										OR (c.system_type_id IN (167,231,165) -- varchar, nvarchar, varbinary
											AND max_length = -1))
										AND i.object_id = @pObjectId) 
							BEGIN SET @pIndexHasLOB = 1 END ELSE BEGIN SET @pIndexHasLOB = 0 END';
						
			EXECUTE @dbContext @SQL, @ParmDefinition1, @pObjectID = @ObjectId, @pIndexHasLOB = @IndexHasLOB OUTPUT;
						
			IF @IndexHasLOB = 1
				BEGIN
					-- offline index operation
					SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOffline; 
					GOTO exec_defrag;
				END;
			ELSE
				BEGIN
					-- online index opreation
					SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOnline;
					GOTO exec_defrag;
				END;
		END;		
		ELSE IF @IndexTypeDesc = 'CLUSTERED INDEX'
		BEGIN
			-- Clustered indexes must be rebuilt offline when the underlying table contains large object (LOB) data types: image, ntext, text, varchar(max), nvarchar(max), varbinary(max), and xml.
			SELECT @SQL = 'IF EXISTS (SELECT 1 FROM information_schema.columns WHERE DATA_TYPE in(''text'',''ntext'',''xml'',''image'') AND TABLE_NAME = @pObjectName) BEGIN SET @pTableHasLOB1 = 1 END ELSE BEGIN SET @pTableHasLOB1 = 0 END';
			EXECUTE @dbContext @SQL, @ParmDefinition2, @pObjectName = @ObjectName, @pTableHasLOB1 = @TableHasLOB1 OUTPUT;
						
			SELECT @SQL = 'IF EXISTS (SELECT 1 FROM information_schema.columns WHERE (DATA_TYPE in(''varchar'',''nvarchar'',''varbinary'') AND CHARACTER_MAXIMUM_LENGTH = -1) AND TABLE_NAME = @pObjectName) BEGIN SET @pTableHasLOB2 = 1 END ELSE BEGIN SET @pTableHasLOB2 = 0 END';
			EXECUTE @dbContext @SQL, @ParmDefinition3, @pObjectName = @ObjectName, @pTableHasLOB2 = @TableHasLOB2 OUTPUT;
						
			IF @TableHasLOB1 = 1 OR @TableHasLOB2 = 1
			BEGIN
				-- rebuild offline
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOffline; 
				GOTO exec_defrag;
			END;
			ELSE
			BEGIN
				-- rebuild online
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOnline;
				GOTO exec_defrag;
			END;
		END;
	END;
			
	-- If SQL Server 2012 or higher
	IF @sqlversion >= 11
	BEGIN
		-- rebuild online fails for XML and spatial index.
		IF (@IndexTypeDesc IN ('PRIMARY XML INDEX','SPATIAL INDEX','XML INDEX'))
		BEGIN
			-- rebuild index offline
			SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOffline; 
			GOTO exec_defrag;
		END;		
		ELSE IF @IndexTypeDesc = 'CLUSTERED INDEX'
		BEGIN
			-- for SQL Server 2012 or higher, Clustered indexes must be rebuilt offline when the underlying table contains the following large object (LOB) data types: image, ntext, and text.
			SELECT @SQL = 'IF EXISTS (SELECT 1 FROM information_schema.columns WHERE DATA_TYPE in(''text'',''ntext'',''image'') AND TABLE_NAME = @pObjectName) BEGIN SET @pTableHasLOB1 = 1 END ELSE BEGIN SET @pTableHasLOB1 = 0 END';
			EXECUTE @dbContext @SQL, @ParmDefinition2, @pObjectName = @ObjectName, @pTableHasLOB1 = @TableHasLOB1 OUTPUT;

			IF @TableHasLOB1 = 1
			BEGIN
				-- rebuild offline
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOffline;
				GOTO exec_defrag;
			END;	
				
			IF @sqlversion = 11 -- if SQL Server 2012
			BEGIN
				-- rebuild online
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOnline;
				GOTO exec_defrag;
			END;	
			ELSE -- if SQL Server 2014 or higher
			BEGIN
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOnlineforSQL2014; 
				GOTO exec_defrag;
			END;
	
		END;
		ELSE
		BEGIN	
			IF @sqlversion = 11 -- if SQL Server 2012
			BEGIN
				-- rebuild online
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOnline; 
				GOTO exec_defrag;
			END;
			ELSE IF @sqlversion > 11 --if SQL Server 2014 or higher
			BEGIN
				SELECT @SQL = N'ALTER INDEX ' + QUOTENAME(@indexname) + N' ON ' + QUOTENAME(@DatabaseName) + N'.'+ QUOTENAME(@ObjectOwner) + N'.' + QUOTENAME(@ObjectName) + @RebuildIndexOnlineforSQL2014; 
				GOTO exec_defrag;
			END;
		END;
	END; 

	exec_defrag:

	BEGIN TRY
		-- go hard or go home!
		EXEC sp_executesql @SQL
		
		-- for debug only - write the ALTER INDEX statement to log
		RAISERROR (@SQL, 10, 1) WITH LOG;
	END TRY
	BEGIN CATCH
		-- ops! something was not good... 
		SELECT @ErrorMessage = ERROR_MESSAGE(), @ErrorSeverity = ERROR_SEVERITY(), @ErrorState = ERROR_STATE(); 
		RAISERROR (@ErrorMessage, @ErrorSeverity, @ErrorState) WITH LOG;
		GOTO next_index;
	END CATCH
	
	next_index:

	-- We've defragged the index time to remove it from #Frag_Info
	DELETE FROM #frag_info WHERE FragInfoID = @FragInfoID;

END; -- end while, stupid!

-- We're done. Byeee!
DROP TABLE #frag_info



GO


