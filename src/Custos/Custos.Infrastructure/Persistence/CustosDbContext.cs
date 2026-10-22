using Microsoft.EntityFrameworkCore;

namespace Custos.Infrastructure.Persistence;

public class CustosDbContext : DbContext
{
    public CustosDbContext(DbContextOptions<CustosDbContext> options) : base(options)
    {
    }
}
