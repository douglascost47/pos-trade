using Ingestao.Domain.Logs;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace Ingestao.Infrastructure.Persistence.Configurations;

public class LogEntityTypeConfiguration : IEntityTypeConfiguration<Log>
{
    public void Configure(EntityTypeBuilder<Log> builder)
    {
        builder.ToTable("Logs");

        builder.HasKey(log => log.Id);

        builder.Property(log => log.Id)
            .UseIdentityColumn();

        builder.Property(log => log.Mensagem)
            .HasMaxLength(500)
            .IsRequired();

        builder.Property(log => log.CriadoEm)
            .IsRequired();

        builder.Ignore(log => log.Eventos);
    }
}
