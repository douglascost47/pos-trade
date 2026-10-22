using Microsoft.EntityFrameworkCore;

namespace Liquidacao.Infrastructure.Persistence;

public class LiquidacaoDbContext : DbContext
{
    public LiquidacaoDbContext(DbContextOptions<LiquidacaoDbContext> options) : base(options)
    {
    }
}
