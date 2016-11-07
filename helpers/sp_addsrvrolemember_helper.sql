USE [master] 
GO
SET NOCOUNT ON
GO
DECLARE @logiName			NVARCHAR(128);
DECLARE @Statement			NVARCHAR(4000);
DECLARE @roleName			NVARCHAR(128);
DECLARE @ParmDefinition_1	NVARCHAR(1024);
DECLARE @Name				NVARCHAR(128);

SET @logiName = N'AMERICAS\ProcessFoglight';
SET @roleName = N'sysadmin';
SET @ParmDefinition_1 = N'@pLogiName NVARCHAR(128),
						@pRoleName NVARCHAR(128)';

IF NOT EXISTS(SELECT name FROM sys.server_principals WHERE name = @logiName)
	BEGIN 
		SET @Statement = N'CREATE LOGIN [' + @logiName + N'] FROM windows WITH default_database = [master]';
		EXECUTE sp_executesql @Statement;
		PRINT N'Login '+ @logiName + N' created!';
	END;
	 
IF NOT EXISTS (SELECT	a.name,c.name 
				FROM sys.server_principals a JOIN sys.server_role_members b
					ON A.principal_id = B.member_principal_id
				JOIN sys.server_principals C
					ON b.role_principal_id = C.principal_id
				WHERE A.[name] = @logiName
				AND c.[name] = @roleName)
	BEGIN
		SET @Statement = N'EXEC master..sp_addsrvrolemember @loginame = @pLogiName, @rolename = @pRoleName';
		EXECUTE sp_executesql @Statement, @ParmDefinition_1, @pLogiName = @logiName, @pRoleName = @roleName;
		PRINT N'Role ' + @roleName + N' granted!';
	END;

SELECT	a.name AS Login,c.name AS Role
FROM sys.server_principals a JOIN sys.server_role_members b
	ON A.principal_id = B.member_principal_id
JOIN sys.server_principals C
	ON b.role_principal_id = C.principal_id
WHERE A.[name] = @logiName;

GO
