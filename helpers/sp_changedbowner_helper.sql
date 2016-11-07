USE [master]
GO
DECLARE @db_name			NVARCHAR (500);
DECLARE @strStatement		NVARCHAR (4000);
DECLARE @ParmDefinition		NVARCHAR(1024);
DECLARE @loginName			NVARCHAR(2);
DECLARE @NewLineChar		AS CHAR(2) = CHAR(13) + CHAR(10);
DECLARE database_curs		CURSOR FOR
								SELECT name FROM   sys.databases
								WHERE SUSER_SNAME(owner_sid) <> 'sa'
SET @loginName = 'sa';
SET @ParmDefinition = N'@pLoginName NVARCHAR(2)'

OPEN database_curs;    
FETCH NEXT FROM database_curs INTO @db_name
WHILE (@@fetch_status <> -1)
BEGIN
	IF (@@fetch_status <> -2)
	BEGIN
		SET @strStatement = N'USE [' + @db_name + N']' + @NewLineChar + 
			N'EXEC sp_changedbowner @loginame = @pLoginName';
		EXECUTE sp_executesql @strStatement,@ParmDefinition,@pLoginName = @loginName;
	END
	FETCH NEXT FROM database_curs INTO @db_name
END;
CLOSE database_curs;
DEALLOCATE database_curs;
GO
