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

builder.Services.AddSingleton<BankingState>();
builder.Services.AddSingleton(_ => BankingOptions.FromConfiguration(builder.Configuration));
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

builder.Services.AddHostedService<BankingStreamProcessorService>();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Module 05 - Banking Streams API (.NET) v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

app.Run();
