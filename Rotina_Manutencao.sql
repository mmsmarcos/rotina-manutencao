/*******************************************************************************************************************************
(C) 2016, Marcos Miguel da Silva

Site: http://www.auxilioerp.com.br/

Feedback: contato@auxilioerp.com.br
*******************************************************************************************************************************/

/*******************************************************************************************************************************
--	Roteiro de Procedimentos para Manutenção de Banco de Dados SQL Server
*******************************************************************************************************************************/

SELECT @@VERSION;

SELECT DB_NAME((SELECT DB_ID(N'corpore'))) AS NOME_BANCO;

SELECT * FROM sys.databases WHERE name = (SELECT DB_NAME((SELECT DB_ID(N'corpore'))));

sp_helpDB corpore

SELECT B.NAME AS NOME_BANCO, 
A.NAME AS NOME_FILE,
	   CASE A.GROUPID 
		    WHEN 1 THEN 'DATA'
		    WHEN 0 THEN 'LOG'
	   END AS 'TIPO FILE', 
       A.FILENAME CAMINHO, 
       A.SIZE*1.0/128 AS TAMANHO_FILE_MB, 
       CASE WHEN A.MAXSIZE = 0 THEN 'AUTOGROWTH DESLIGADO' 
            WHEN A.MAXSIZE = -1 THEN 'AUTOGROWTH LIGADO' 
            ELSE 'FILE CRESCERA A UM TAMANHO MAX DE 2TB' END AS STATUS_AUTOGROWTH, 
       A.GROWTH AS 'CRESCIMENTO MB', 
       'INCREMENTO DE CRESCIMENTO' = CASE WHEN A.GROWTH = 0 THEN 'TAMANHO FIXO' 
                                WHEN A.GROWTH > 0 THEN 'CRESCIMENTO EM PAG DE 8 KB' 
								ELSE 'CRESCIMENTO EM %' 
							END,
	   GETDATE() AS 'DATA'
FROM MASTER..SYSALTFILES A 
	INNER JOIN MASTER..SYSDATABASES B
      ON B.DBID = A.DBID


DBCC OPENTRAN; --identificar as transações ativas que podem impedir o truncamento do log

--------------------------------------------------------------------------------------------------------------------------------
--	1)	Execute o DBCC Checkdb periodicamente. Obs: Executar esse comando quando banco não estiver em produção!!!
--------------------------------------------------------------------------------------------------------------------------------
ALTER DATABASE CorporeRM SET SINGLE_USER
WITH ROLLBACK IMMEDIATE;
GO                      --Executa reparos que não têm nenhuma possibilidade de perda de dados.
DBCC CHECKDB(CorporeRM, REPAIR_REBUILD)
WITH ALL_ERRORMSGS, NO_INFOMSGS
--1h21min10ss
GO
ALTER DATABASE CorporeRM SET MULTI_USER
--------------------------------------------------------------------------------------------------------------------------------
--	2) Use DBCC Checksum com backup de log.
--------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------------------
--	3) Execute DBCC SHRINKDATABASE (UserDB, 10) para reduzir o tamanho do banco de dados.
--------------------------------------------------------------------------------------------------------------------------------
USE Corpore;  
GO  
EXEC sp_spaceused N'dbo.TMOV';  


USE master;  
GO  
SELECT file_id, name, type_desc, physical_name, size, max_size  
FROM sys.database_files ;  

/*

-- Para reduzir um arquivo de dados ou de log de cada vez DBCC SHRINKFILE
-- Para reduzir todos os arquivos de dados e log de um banco de dados DBCC SHRINKDATABASE

########################################################################################################################
		A menos que você tenha um requisito específico, não defina a opção de banco de dados AUTO_SHRINK como ON.
########################################################################################################################


Estimativa de Tempo na Base de Dados
DBCC SHRINKDATABASE (CorporeRM, 10)
--10h21
--13h59
*/

--------------------------------------------------------------------------------------------------------------------------------
--	4) Execute EXEC sp_updatestats periodicamente. (Executar também após executar o Shrinkdatabase)
--------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------------------
--	5) Monitoramento de Disco
--------------------------------------------------------------------------------------------------------------------------------

-- Calculates average stalls per read, per write, and per total input/output
-- for each database file.
SELECT DB_NAME(database_id) AS [Database Name] , 
       file_id , 
	   io_stall_read_ms , 
	   num_of_reads , 
	   CAST(io_stall_read_ms / ( 1.0 + num_of_reads ) AS NUMERIC(10, 1)) AS [avg_read_stall_ms],
	   io_stall_write_ms, 
	   num_of_writes ,
       CAST(io_stall_write_ms / ( 1.0 + num_of_writes ) AS NUMERIC(10, 1)) AS [avg_write_stall_ms], 
	   io_stall_read_ms + io_stall_write_ms AS [io_stalls] , 
	   num_of_reads + num_of_writes AS [total_io] , 
	   CAST(( io_stall_read_ms + io_stall_write_ms ) / ( 1.0 + num_of_reads + num_of_writes) AS NUMERIC(10,1)) AS [avg_io_stall_ms]
  FROM sys.dm_io_virtual_file_stats(NULL, NULL)
 ORDER BY avg_io_stall_ms DESC ;


-- Look at pending I/O requests by file
SELECT DB_NAME(mf.database_id) AS [Database] , mf.physical_name ,r.io_pending , r.io_pending_ms_ticks , r.io_type , fs.num_of_reads , fs.num_of_writes
FROM sys.dm_io_pending_io_requests AS r INNER JOIN sys.dm_io_virtual_file_stats(NULL, NULL) AS fs ON r.io_handle = fs.file_handle INNER JOIN sys.master_files AS mf ON fs.database_id = mf.database_id
AND fs.file_id = mf.file_id ORDER BY r.io_pending , r.io_pending_ms_ticks DESC ;



 --leitura
	SELECT TOP 5 DB_NAME(database_id) AS [Database Name]
			, file_id 
			, io_stall_read_ms
			, num_of_reads
			, CAST(io_stall_read_ms/(1.0 + num_of_reads) AS NUMERIC(10,1)) AS [avg_read_stall_ms]
		
			, io_stall_read_ms + io_stall_write_ms AS [io_stalls]
			, num_of_reads + num_of_writes AS [total_io]
			, CAST((io_stall_read_ms + io_stall_write_ms)/(1.0 + num_of_reads + num_of_writes) AS NUMERIC(10,1)) AS [avg_io_stall_ms]
			, GETDATE() as [Dt_Registro]
	FROM sys.dm_io_virtual_file_stats(null,null)
	order by 5 desc


--escrita
	SELECT TOP 5 DB_NAME(database_id) AS [Database Name]
			, file_id 
				, io_stall_write_ms
			, num_of_writes
			, CAST(io_stall_write_ms/(1.0+num_of_writes) AS NUMERIC(10,1)) AS [avg_write_stall_ms]
			, io_stall_read_ms + io_stall_write_ms AS [io_stalls]
			, num_of_reads + num_of_writes AS [total_io]
			, CAST((io_stall_read_ms + io_stall_write_ms)/(1.0 + num_of_reads + num_of_writes) AS NUMERIC(10,1)) AS [avg_io_stall_ms]
			, GETDATE() as [Dt_Registro]
	FROM sys.dm_io_virtual_file_stats(null,null)
	order by 5 desc


--caso de um valor alto na coluna [avg_io_stall_ms], confira os contadores abeixo no Perfmon.
Avg Disk Sec/Read - Validar se a latência do disco está dentro da expectativa. Em geral, adotam-se valores máximos de 50 a 100ms como tempo de respostas para o disco de dados. Uma sugestão de tempos:
  
      <1ms : inacreditável
      <3ms : excelente
      <5ms : muito bom
      <10ms : dentro do esperado
      <20ms : razoável
      <50ms : limite
      >100ms : ruim
      > 1 seg : contenção severa de disco
      > 15 seg : problemas graves com o storage

     
Avg Disk Sec/Write - Validar se a latência do disco está dentro da expectativa. Ignore esse valor para os discos de dados. Utilize esse contador para os discos de log com latências reduzidas:
  
      <1ms : excelente
      <3ms : bom
      <5ms : razoável
      <10ms : limite
      >20ms : ruim
      > 1 seg : contenção severa de disco
      > 15 seg : problemas graves com o storage