using Microsoft.EntityFrameworkCore;

namespace Alocacao.Infrastructure.Persistence;

public class AlocacaoDbContext : DbContext
{
    public AlocacaoDbContext(DbContextOptions<AlocacaoDbContext> options) : base(options)
    {
    }
}
