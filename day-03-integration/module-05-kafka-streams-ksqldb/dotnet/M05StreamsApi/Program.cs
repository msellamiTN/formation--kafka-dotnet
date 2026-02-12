using Confluent.Kafka;
using Microsoft.OpenApi.Models;
using M05StreamsApi.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Module 05 - Banking Streams API (.NET)",
        Version = "v1"
    });
});

// Banking services (transactions, balances)
builder.Services.AddSingleton<BankingState>();
builder.Services.AddSingleton(_ => BankingOptions.FromConfiguration(builder.Configuration));

// Sales Streams services (sales, aggregations, state stores)
builder.Services.AddSingleton<StreamsState>();
builder.Services.AddSingleton(_ => StreamsOptions.FromConfiguration(builder.Configuration));

// Shared Kafka producer
builder.Services.AddSingleton<IProducer<string, string>>(sp =>
{
    var bootstrapServers = builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092";
    var clientId = builder.Configuration["Kafka:ClientId"] ?? "m05-streams-api-dotnet";
    var config = new ProducerConfig
    {
        BootstrapServers = bootstrapServers,
        ClientId = clientId
    };

    return new ProducerBuilder<string, string>(config).Build();
});

// Background processors
builder.Services.AddHostedService<BankingStreamProcessorService>();
builder.Services.AddHostedService<SalesStreamProcessorService>();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Module 05 - Banking Streams API (.NET) v1");
    c.RoutePrefix = "swagger";
});

// Root endpoint
app.MapGet("/", () => Results.Ok(new
{
    application = "Module 05 - Banking Streams API (.NET)",
    version = "1.0.0",
    endpoints = new
    {
        swagger = "/swagger",
        health = "/api/v1/health",
        sales = "POST /api/v1/sales",
        statsByProduct = "GET /api/v1/stats/by-product",
        statsPerMinute = "GET /api/v1/stats/per-minute",
        transactions = "POST /api/v1/transactions",
        balances = "GET /api/v1/balances",
        stores = "GET /api/v1/stores/{storeName}/all"
    }
}));

app.MapControllers();

app.Run();
