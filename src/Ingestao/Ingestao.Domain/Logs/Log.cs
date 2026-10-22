namespace Ingestao.Domain.Logs;

public class Log
{
    private readonly List<LogRegistradoEvent> _eventos = new();

    public int Id { get; private set; }
    public string Mensagem { get; private set; } = string.Empty;
    public DateTimeOffset CriadoEm { get; private set; }

    public IReadOnlyCollection<LogRegistradoEvent> Eventos => _eventos;

    private Log()
    {
    }

    public static Log Registrar(string mensagem)
    {
        return new Log
        {
            Mensagem = mensagem,
            CriadoEm = DateTimeOffset.UtcNow
        };
    }

    public void NotificarRegistro()
    {
        _eventos.Add(new LogRegistradoEvent(Id, Mensagem, CriadoEm));
    }
}
