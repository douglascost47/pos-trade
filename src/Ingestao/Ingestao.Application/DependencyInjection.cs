using Ingestao.Application.Logs;
using Microsoft.Extensions.DependencyInjection;

namespace Ingestao.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        services.AddScoped<RegistrarLogUseCase>();

        return services;
    }
}
