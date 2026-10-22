namespace Ingestao.Domain.Logs;

public record LogRegistradoEvent(int LogId, string Mensagem, DateTimeOffset OcorridoEm);
