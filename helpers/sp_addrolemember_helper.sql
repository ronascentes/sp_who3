USE [master] 
GO
SET NOCOUNT ON
GO
DECLARE @userName			NVARCHAR(128);
DECLARE @Statement			NVARCHAR(4000);
DECLARE @dbName				NVARCHAR(128);
DECLARE @roleName			NVARCHAR(128);
DECLARE @ParmDefinition_1	NVARCHAR(1024);
DECLARE @ParmDefinition_2	NVARCHAR(1024);
DECLARE @Name				NVARCHAR(128);
DECLARE @dbContext			NVARCHAR(256)= @dbName + '.dbo.' + 'sp_executeSQL';
DECLARE @NewLineChar		AS CHAR(2) = CHAR(13) + CHAR(10);

SET @userName = 'Americas\Bill_Tyrrell';
SET @dbName = 'Harmony_Global';
SET @roleName = 'HARMONY_REPORTING_RPT';
SET @ParmDefinition_1 = N'@pRoleName NVARCHAR(128),
						@pUserName NVARCHAR(128)';

IF NOT EXISTS(SELECT name FROM sys.server_principals WHERE name = @userName)
BEGIN 
	SET @Statement = N'CREATE LOGIN [' + @UserName + N'] FROM windows WITH default_database = [master]';
	EXECUTE sp_executesql @Statement;

	SET @Statement = N'USE [' + @dbName + N']' + @NewLineChar +
		N'CREATE USER [' + @UserName + N'] FOR LOGIN [' + @UserName + N']';
	EXECUTE sp_executesql @Statement;

	SET @Statement = N'USE [' + @dbName + N']' + @NewLineChar +
		N'EXEC Sp_addrolemember @rolename = @pRoleName, @membername = @pUserName';
	EXECUTE sp_executesql @Statement, @ParmDefinition_1, @pRoleName = @roleName, @pUserName = @userName;
 
	PRINT N'Login and User created. Role added also.';
END;
ELSE
BEGIN
	SET @Statement = N'SELECT @pNameOUT = name FROM sys.database_principals WHERE name = @pUserName';	
	SET @dbContext = @dbName + '.dbo.' + 'sp_executeSQL';
	SET @ParmDefinition_2 = N'@pUserName NVARCHAR(128),
							@pNameOUT NVARCHAR (128) OUTPUT';
	EXECUTE @dbContext @Statement,
						@ParmDefinition_2,
						@pUserName = @userName,
						@pNameOUT = @Name OUTPUT;
	
	IF (SELECT @Name) IS NULL
	BEGIN
		SET @Statement = N'USE [' + @dbName + N']' + @NewLineChar +
			N'CREATE USER [' + @UserName + N'] FOR LOGIN [' + @UserName + N']';
		EXECUTE sp_executesql @Statement;
	
		SET @Statement = N'USE [' + @dbName + N']' + @NewLineChar +
			N'EXEC Sp_addrolemember @rolename = @pRoleName, @membername = @pUserName';
		EXECUTE sp_executesql @Statement, @ParmDefinition_1, @pRoleName = @roleName, @pUserName = @userName;
		
		PRINT N'User created and role added!';
	END;
	ElSE
	BEGIN
		SET @Statement = N'USE [' + @dbName + N']' + @NewLineChar +
			N'EXEC Sp_addrolemember @rolename = @pRoleName, @membername = @pUserName';
		EXECUTE sp_executesql @Statement, @ParmDefinition_1, @pRoleName = @roleName, @pUserName = @userName;
	
		PRINT N'Role added!';
	END;
END;
GO
