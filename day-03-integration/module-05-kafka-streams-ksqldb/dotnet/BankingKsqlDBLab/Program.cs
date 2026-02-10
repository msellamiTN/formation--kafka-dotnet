using BankingKsqlDBLab.Services;
using BankingKsqlDBLab.Producers;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Banking ksqlDB Lab API",
        Version = "v1",
        Description = "E-Banking stream processing with ksqlDB and C# .NET"
    });
});

var ksqlDbUrl = builder.Configuration["KsqlDB:Url"] ?? "http://localhost:8088";
var kafkaBootstrap = builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092";

builder.Services.AddSingleton(sp =>
    new KsqlDbService(ksqlDbUrl, sp.GetRequiredService<ILogger<KsqlDbService>>()));

builder.Services.AddSingleton(sp =>
    new TransactionProducer(kafkaBootstrap, sp.GetRequiredService<ILogger<TransactionProducer>>()));

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Banking ksqlDB Lab API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

// Do NOT auto-initialize on startup; use POST /api/TransactionStream/initialize instead
app.Run();
