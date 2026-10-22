-- Tabela do exemplo de teste de log/Seq da Ingestão (Ingestao.Domain.Logs.Log).
-- Idempotente: pode rodar várias vezes. Normalmente as tabelas vêm das migrations do EF Core;
-- este script cobre o cenário de ambiente local sem `dotnet ef database update`.

USE PosTrade_Ingestao;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'Logs')
BEGIN
    CREATE TABLE dbo.Logs
    (
        Id        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        Mensagem  NVARCHAR(500)     NOT NULL,
        CriadoEm  DATETIMEOFFSET    NOT NULL
    );
END
GO
