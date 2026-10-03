-- Um banco por serviço (database per service). Idempotente: pode rodar várias vezes.
-- As tabelas são criadas depois pelas migrations do EF Core de cada serviço.

IF DB_ID('PosTrade_Ingestao')   IS NULL CREATE DATABASE PosTrade_Ingestao;
IF DB_ID('PosTrade_Alocacao')   IS NULL CREATE DATABASE PosTrade_Alocacao;
IF DB_ID('PosTrade_Custos')     IS NULL CREATE DATABASE PosTrade_Custos;
IF DB_ID('PosTrade_Liquidacao') IS NULL CREATE DATABASE PosTrade_Liquidacao;
GO

-- READ_COMMITTED_SNAPSHOT: leitores não bloqueiam escritores (Bloco 5 do guia).
ALTER DATABASE PosTrade_Ingestao   SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PosTrade_Alocacao   SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PosTrade_Custos     SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
ALTER DATABASE PosTrade_Liquidacao SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;
GO

SELECT name, is_read_committed_snapshot_on
FROM sys.databases
WHERE name LIKE 'PosTrade_%'
ORDER BY name;
GO
