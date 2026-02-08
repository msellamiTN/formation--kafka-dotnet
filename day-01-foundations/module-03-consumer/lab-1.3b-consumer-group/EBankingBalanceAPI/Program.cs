using EBankingBalanceAPI.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Register Kafka Consumer as a Singleton Background Service
builder.Services.AddSingleton<BalanceConsumerService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<BalanceConsumerService>());

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Balance API",
        Version = "v1",
        Description = "Real-time Kafka Consumer Group for customer balance computation."
    });
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Balance API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

app.Run();
