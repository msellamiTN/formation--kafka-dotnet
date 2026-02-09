using EBankingSerializationAPI.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Register Kafka Serialization Producer as a Singleton
builder.Services.AddSingleton<SerializationProducerService>();

// Register background consumer for schema evolution demo (commented out for deployment)
// builder.Services.AddSingleton<SchemaEvolutionConsumerService>();
// builder.Services.AddHostedService(sp => sp.GetRequiredService<SchemaEvolutionConsumerService>());

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Serialization API",
        Version = "v1",
        Description = "Lab 2.1 — Typed JSON serialization with schema validation and evolution.\n\n"
            + "**Concepts demonstrated:**\n"
            + "- Custom `ISerializer<Transaction>` with validation before Kafka send\n"
            + "- Custom `IDeserializer<Transaction>` with BACKWARD/FORWARD compatibility\n"
            + "- Schema evolution (v1 → v2) with optional fields\n"
            + "- Schema version tracking via Kafka headers\n\n"
            + "**Endpoints:**\n"
            + "- `POST /api/transactions` — Send transaction with typed serializer (validated)\n"
            + "- `POST /api/transactions/v2` — Send v2 transaction (with riskScore field)\n"
            + "- `GET /api/transactions/schema-info` — Show current schema versions\n"
            + "- `GET /api/transactions/consumed` — List recently consumed messages with schema info\n"
            + "- `GET /api/transactions/metrics` — Serialization metrics"
    });
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Serialization API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

// Health check
app.MapGet("/health", () => Results.Ok(new
{
    status = "healthy",
    service = "ebanking-serialization-api",
    timestamp = DateTime.UtcNow
}));

var logger = app.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("========================================");
logger.LogInformation("  E-Banking Serialization API (Lab 2.1)");
logger.LogInformation("  Bootstrap  : {Servers}", builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092");
logger.LogInformation("  Topic      : {Topic}", builder.Configuration["Kafka:Topic"] ?? "banking.transactions");
logger.LogInformation("========================================");

app.Run();
