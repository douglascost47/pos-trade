using Ingestao.Domain.Logs;
using Microsoft.Extensions.Logging;

namespace Ingestao.Application.Logs;

public class RegistrarLogUseCase
{
    private readonly ILogRepository _repositorio;
    private readonly ILogger<RegistrarLogUseCase> _logger;

    public RegistrarLogUseCase(ILogRepository repositorio, ILogger<RegistrarLogUseCase> logger)
    {
        _repositorio = repositorio;
        _logger = logger;
    }

    public async Task<LogResultado> ExecutarAsync(CancellationToken cancellationToken)
    {
        var log = Log.Registrar($"Log de teste disparado pela Ingestão em {DateTimeOffset.Now}");

        await _repositorio.AdicionarAsync(log, cancellationToken);
        await _repositorio.SalvarAlteracoesAsync(cancellationToken);

        // O Id é gerado pelo banco (IDENTITY), por isso o evento só pode ser
        // construído depois que a infraestrutura persiste e preenche o Id.
        log.NotificarRegistro();

        foreach (var evento in log.Eventos)
        {
            _logger.LogInformation(
                "Evento {Evento} publicado: LogId={LogId}, Mensagem={Mensagem}, OcorridoEm={OcorridoEm}",
                nameof(LogRegistradoEvent),
                evento.LogId,
                evento.Mensagem,
                evento.OcorridoEm);
        }

        return new LogResultado(log.Id, log.Mensagem, log.CriadoEm);
    }
}
