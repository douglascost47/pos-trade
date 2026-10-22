using Ingestao.Domain.Logs;

namespace Ingestao.Application.Logs;

public interface ILogRepository
{
    Task AdicionarAsync(Log log, CancellationToken cancellationToken);

    Task SalvarAlteracoesAsync(CancellationToken cancellationToken);
}
