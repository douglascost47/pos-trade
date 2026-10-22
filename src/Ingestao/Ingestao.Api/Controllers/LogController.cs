using Ingestao.Application.Logs;
using Microsoft.AspNetCore.Mvc;

namespace Ingestao.Api.Controllers;

[ApiController]
[Route("api/logs")]
public class LogController : ControllerBase
{
    private readonly RegistrarLogUseCase _useCase;

    public LogController(RegistrarLogUseCase useCase)
    {
        _useCase = useCase;
    }

    [HttpGet]
    public async Task<ActionResult<LogResultado>> Get(CancellationToken cancellationToken)
    {
        var resultado = await _useCase.ExecutarAsync(cancellationToken);
        return Ok(resultado);
    }
}
