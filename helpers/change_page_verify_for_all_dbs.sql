USE [master]
GO
DECLARE @db_name			NVARCHAR (500);
DECLARE @strStatement		NVARCHAR (4000);
DECLARE database_curs		CURSOR FOR
								SELECT name FROM   sys.databases;

OPEN database_curs;    
FETCH NEXT FROM database_curs INTO @db_name
WHILE (@@fetch_status <> -1)
BEGIN
	IF (@@fetch_status <> -2)
	BEGIN
		SET @strStatement = N'ALTER DATABASE [' + @db_name + N'] SET PAGE_VERIFY CHECKSUM';
		EXECUTE sp_executesql @strStatement;
	END
	FETCH NEXT FROM database_curs INTO @db_name
END;
CLOSE database_curs;
DEALLOCATE database_curs;
GO