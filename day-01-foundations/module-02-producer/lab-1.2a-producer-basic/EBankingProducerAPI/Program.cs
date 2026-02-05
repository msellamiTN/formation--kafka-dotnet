using EBankingProducerAPI.Services;
using Microsoft.OpenApi.Models;
using System.Reflection;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllers();

// Register Kafka Producer as Singleton
builder.Services.AddSingleton<KafkaProducerService>();

// Configure Swagger/OpenAPI
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Producer API",
        Version = "v1",
        Description = "API for processing banking transactions with Apache Kafka integration.\n\n" +
                      "This API demonstrates:\n" +
                      "- Kafka Producer configuration and message sending\n" +
                      "- E-Banking transaction processing\n" +
                      "- OpenAPI documentation and testing\n" +
                      "- Delivery metadata (partition, offset, timestamp)",
        Contact = new OpenApiContact
        {
            Name = "E-Banking Development Team",
            Email = "dev@ebanking.com"
        }
    });

    // Include XML comments for Swagger documentation
    var xmlFilename = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFilename);
    if (File.Exists(xmlPath))
    {
        options.IncludeXmlComments(xmlPath);
    }
});

// Add CORS for development
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "E-Banking Producer API v1");
    options.RoutePrefix = "swagger";
    options.DocumentTitle = "E-Banking Producer API - Swagger UI";
});

app.UseCors();
app.UseAuthorization();
app.MapControllers();

// Log startup information
var logger = app.Services.GetRequiredService<ILogger<Program>>();
var kafkaBootstrap = builder.Configuration["Kafka:BootstrapServers"] ?? "localhost:9092";
var kafkaTopic = builder.Configuration["Kafka:Topic"] ?? "banking.transactions";

logger.LogInformation("===========================================");
logger.LogInformation("  E-Banking Producer API Starting...");
logger.LogInformation("  Kafka Bootstrap: {Bootstrap}", kafkaBootstrap);
logger.LogInformation("  Kafka Topic: {Topic}", kafkaTopic);
logger.LogInformation("  Swagger UI: https://localhost:5001/swagger");
logger.LogInformation("===========================================");

app.Run();
