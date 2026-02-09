using EBankingIdempotentProducerAPI.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Register both producers as Singletons for side-by-side comparison
builder.Services.AddSingleton<IdempotentProducerService>();
builder.Services.AddSingleton<NonIdempotentProducerService>();

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Idempotent Producer API",
        Version = "v1",
        Description = "Lab 2.2 — Producer idempotence and exactly-once semantics.\n\n"
            + "**Two producers side-by-side:**\n"
            + "- **Idempotent** (`EnableIdempotence=true`): PID + sequence numbers, no duplicates on retry\n"
            + "- **Non-idempotent** (`EnableIdempotence=false`): risk of duplicates on retry\n\n"
            + "**Endpoints:**\n"
            + "- `POST /api/transactions/idempotent` — Send with idempotent producer\n"
            + "- `POST /api/transactions/non-idempotent` — Send with non-idempotent producer\n"
            + "- `POST /api/transactions/batch` — Batch send with both, compare results\n"
            + "- `GET /api/transactions/metrics` — PID info, sequence numbers, config comparison\n"
            + "- `GET /api/transactions/compare` — Side-by-side config comparison"
    });
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Idempotent Producer API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

// Health check
app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "ebanking-idempotent-producer-api",
    timestamp = DateTime.UtcNow
}));

var logger = app.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("========================================");
logger.LogInformation("  E-Banking Idempotent Producer API (Lab 2.2)");
logger.LogInformation("  Bootstrap  : {Servers}", builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092");
logger.LogInformation("  Topic      : {Topic}", builder.Configuration["Kafka:Topic"] ?? "banking.transactions");
logger.LogInformation("========================================");

app.Run();
