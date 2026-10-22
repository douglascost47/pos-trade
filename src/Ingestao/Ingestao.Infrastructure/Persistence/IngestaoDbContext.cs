using Ingestao.Domain.Logs;
using Microsoft.EntityFrameworkCore;

namespace Ingestao.Infrastructure.Persistence;

public class IngestaoDbContext : DbContext
{
    public IngestaoDbContext(DbContextOptions<IngestaoDbContext> options) : base(options)
    {
    }

    public DbSet<Log> Logs => Set<Log>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(IngestaoDbContext).Assembly);
    }
}
