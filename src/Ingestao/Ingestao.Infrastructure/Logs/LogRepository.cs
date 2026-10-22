using Ingestao.Application.Logs;
using Ingestao.Domain.Logs;
using Ingestao.Infrastructure.Persistence;

namespace Ingestao.Infrastructure.Logs;

public class LogRepository : ILogRepository
{
    private readonly IngestaoDbContext _dbContext;

    public LogRepository(IngestaoDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task AdicionarAsync(Log log, CancellationToken cancellationToken)
    {
        await _dbContext.Logs.AddAsync(log, cancellationToken);
    }

    public Task SalvarAlteracoesAsync(CancellationToken cancellationToken)
    {
        return _dbContext.SaveChangesAsync(cancellationToken);
    }
}
