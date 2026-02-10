using EBankingTransactionsAPI.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<TransactionalProducerService>();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Transactional Producer API",
        Version = "v1",
        Description = "API de transactions avec Exactly-Once Semantics (EOS) utilisant les transactions Kafka.\n\n"
            + "**Garantie : Exactly-Once Semantics**\n"
            + "- Aucune perte de messages\n"
            + "- Aucun duplicata\n"
            + "- Atomicité multi-messages\n\n"
            + "**Endpoints :**\n"
            + "- `POST /api/transactions/single` - Transaction unique atomique\n"
            + "- `POST /api/transactions/batch` - Lot de transactions atomiques\n"
            + "- `GET /api/transactions/metrics` - Métriques transactionnelles\n"
            + "- `GET /api/transactions/health` - Health check",
        Contact = new OpenApiContact { Name = "E-Banking Team" }
    });
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Transactional Producer API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

var logger = app.Services.GetRequiredService<ILogger<Program>>();
logger.LogInformation("========================================");
logger.LogInformation("  E-Banking Transactional Producer API (Lab 2.2b)");
logger.LogInformation("  Bootstrap  : {Servers}", builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092");
logger.LogInformation("  Topic      : {Topic}", builder.Configuration["Kafka:Topic"] ?? "banking.transactions");
logger.LogInformation("  TxID       : {TxId}", builder.Configuration["Kafka:TransactionalId"] ?? "ebanking-payment-producer");
logger.LogInformation("========================================");

app.Run();
