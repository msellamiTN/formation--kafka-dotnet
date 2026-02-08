using EBankingResilientProducerAPI.Services;
using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddSingleton<ResilientKafkaProducerService>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.Models.OpenApiInfo
    {
        Title = "E-Banking Resilient Producer API",
        Version = "v1",
        Description = "API de transactions bancaires avec gestion d'erreurs production-ready.\n\n"
            + "**Fonctionnalités :**\n"
            + "- Retry avec exponential backoff (1s, 2s, 4s)\n"
            + "- Dead Letter Queue (DLQ) pour transactions échouées\n"
            + "- Circuit breaker (seuil: 5 échecs consécutifs)\n"
            + "- Fallback fichier local si DLQ échoue\n"
            + "- Métriques temps réel\n\n"
            + "**Endpoints :**\n"
            + "- `POST /api/transactions` — Transaction avec retry + DLQ\n"
            + "- `POST /api/transactions/batch` — Lot avec rapport d'erreurs\n"
            + "- `GET /api/transactions/metrics` — Métriques du producer\n"
            + "- `GET /api/transactions/health` — Health + circuit breaker"
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "E-Banking Resilient Producer API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

var logger = app.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("========================================");
logger.LogInformation("  E-Banking Resilient Producer API");
logger.LogInformation("  Bootstrap  : {Servers}", builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092");
logger.LogInformation("  Topic      : {Topic}", builder.Configuration["Kafka:Topic"] ?? "banking.transactions");
logger.LogInformation("  DLQ Topic  : {Dlq}", builder.Configuration["Kafka:DlqTopic"] ?? "banking.transactions.dlq");
logger.LogInformation("========================================");

app.Run();
