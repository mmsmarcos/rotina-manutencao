IF NOT EXISTS (
	select name
	from sys.databases 
	where name = 'Traces'
)
BEGIN
	CREATE DATABASE [Traces] 
		ON  PRIMARY ( 
			NAME = N'Traces', FILENAME = N'C:\Bases\Traces.mdf' , 
			SIZE = 500 MB , FILEGROWTH = 500 MB 
		)
		LOG ON ( 
			NAME = N'Traces_log', FILENAME = N'C:\Bases\Traces_log.ldf' , 
			SIZE = 100 MB , FILEGROWTH = 100 MB 
		)
END
GO
ALTER DATABASE [Traces] SET RECOVERY SIMPLE

USE Traces
GO


IF (OBJECT_ID('[dbo].[CheckList_Espaco_Disco]') IS NOT NULL)
	DROP TABLE [dbo].[CheckList_Espaco_Disco]

CREATE TABLE [dbo].[CheckList_Espaco_Disco] (
	[DriveName]			VARCHAR(256) NULL,
	[TotalSize_GB]		BIGINT NULL,
	[FreeSpace_GB]		BIGINT NULL,
	[SpaceUsed_GB]		BIGINT NULL,
	[SpaceUsed_Percent] DECIMAL(9, 3) NULL
)

EXEC sp_configure 'show advanced option',1

RECONFIGURE

EXEC sp_configure 'Ole Automation Procedures',1

RECONFIGURE
 
EXEC sp_configure 'show advanced option',0

RECONFIGURE


CREATE PROCEDURE [dbo].[stpCheckList_Espaco_Disco]
AS
BEGIN
	SET NOCOUNT ON 

	CREATE TABLE #dbspace (
		[Name]		SYSNAME,
		[Caminho]	VARCHAR(200),
		[Tamanho]	VARCHAR(10),
		[Drive]		VARCHAR(30)
	)

	CREATE TABLE [#espacodisco] (
		[Drive]				VARCHAR(10) ,
		[Tamanho (MB)]		INT,
		[Usado (MB)]		INT,
		[Livre (MB)]		INT,
		[Livre (%)]			INT,
		[Usado (%)]			INT,
		[Ocupado SQL (MB)]	INT, 
		[Data]				SMALLDATETIME
	)

	EXEC sp_MSforeachdb '	Use [?] 
							INSERT INTO #dbspace 
							SELECT	CONVERT(VARCHAR(25), DB_NAME())''Database'', CONVERT(VARCHAR(60), FileName),
									CONVERT(VARCHAR(8), Size/128) ''Size in MB'', CONVERT(VARCHAR(30), Name) 
							FROM [sysfiles]'

	DECLARE @hr INT, @fso INT, @size FLOAT, @TotalSpace INT, @MBFree INT, @Percentage INT, 
			@SQLDriveSize INT, @drive VARCHAR(1), @fso_Method VARCHAR(255), @mbtotal INT = 0	
	
	EXEC @hr = [master].[dbo].[sp_OACreate] 'Scripting.FilesystemObject', @fso OUTPUT

	IF (OBJECT_ID('tempdb..#space') IS NOT NULL) 
		DROP TABLE #space

	CREATE TABLE #space (
		[drive] CHAR(1), 
		[mbfree] INT
	)
	
	INSERT INTO #space EXEC [master].[dbo].[xp_fixeddrives]
	
	DECLARE CheckDrives Cursor For SELECT [drive], [mbfree] 
	FROM #space
	
	Open CheckDrives
	FETCH NEXT FROM CheckDrives INTO @drive, @MBFree
	WHILE(@@FETCH_STATUS = 0)
	BEGIN
		SET @fso_Method = 'Drives("' + @drive + ':").TotalSize'
		
		SELECT @SQLDriveSize = SUM(CONVERT(INT, Tamanho)) 
		FROM #dbspace 
		WHERE SUBSTRING(Caminho, 1, 1) = @drive
		
		EXEC @hr = sp_OAMethod @fso, @fso_Method, @size OUTPUT
		
		SET @mbtotal = @size / (1024 * 1024)
		
		INSERT INTO #espacodisco 
		VALUES(	@drive + ':', @mbtotal, @mbtotal-@MBFree, @MBFree, (100 * round(@MBFree, 2) / round(@mbtotal, 2)), 
				(100 - 100 * round(@MBFree,2) / round(@mbtotal, 2)), @SQLDriveSize, GETDATE())

		FETCH NEXT FROM CheckDrives INTO @drive, @MBFree
	END
	CLOSE CheckDrives
	DEALLOCATE CheckDrives

	TRUNCATE TABLE [dbo].[CheckList_Espaco_Disco]
	
	INSERT INTO [dbo].[CheckList_Espaco_Disco]( [DriveName], [TotalSize_GB], [FreeSpace_GB], [SpaceUsed_GB], [SpaceUsed_Percent] )
	SELECT [Drive], [Tamanho (MB)], [Livre (MB)], [Usado (MB)], [Usado (%)] 
	FROM #espacodisco

	IF (@@ROWCOUNT = 0)
	BEGIN
		INSERT INTO [dbo].[CheckList_Espaco_Disco]( [DriveName], [TotalSize_GB], [FreeSpace_GB], [SpaceUsed_GB], [SpaceUsed_Percent] )
		SELECT 'Sem registro de Espaço em Disco', NULL, NULL, NULL, NULL
	END
END


/*
	Nessa etapa cria-se um JOB para executar a cada 10 minutos com a informação do disco
*/
EXEC [dbo].[stpCheckList_Espaco_Disco]
GO
IF EXISTS (SELECT * FROM [dbo].[CheckList_Espaco_Disco] WHERE SpaceUsed_Percent >= 85)
BEGIN
	EXEC MSDB..SP_SEND_DBMAIL
	@profile_name = 'Marcos',
	@RECIPIENTS = 'marcos.miguel@ambientispar.com.br',
	@SUBJECT = 'Notificação Marcos Database', 
	@BODY = 'Disco está cheio!'
END