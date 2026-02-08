using EBankingKeyedProducerAPI.Services;
using Microsoft.OpenApi.Models;
using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddSingleton<KeyedKafkaProducerService>();

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Keyed Producer API",
        Version = "v1",
        Description = "API de transactions bancaires avec partitionnement par CustomerId.\n\n"
            + "**Partitionnement** : `partition = murmur2(CustomerId) % 6`\n\n"
            + "**Endpoints :**\n"
            + "- `POST /api/transactions` — Transaction avec clé CustomerId\n"
            + "- `POST /api/transactions/batch` — Lot de transactions\n"
            + "- `GET /api/transactions/stats/partitions` — Distribution par partition\n"
            + "- `GET /api/transactions/health` — Health check"
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "E-Banking Keyed Producer API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

var logger = app.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("========================================");
logger.LogInformation("  E-Banking Keyed Producer API Starting...");
logger.LogInformation("  Partitioning: CustomerId (Murmur2)");
logger.LogInformation("  Kafka      : {Servers}", builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092");
logger.LogInformation("  Topic      : {Topic}", builder.Configuration["Kafka:Topic"] ?? "banking.transactions");
logger.LogInformation("========================================");

app.Run();
