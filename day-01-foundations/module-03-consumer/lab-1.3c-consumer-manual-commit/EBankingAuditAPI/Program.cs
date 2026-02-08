using EBankingAuditAPI.Services;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Register Kafka Consumer as a Singleton Background Service
builder.Services.AddSingleton<AuditConsumerService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<AuditConsumerService>());

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "E-Banking Audit & Compliance API",
        Version = "v1",
        Description = "Kafka Consumer with manual commit for regulatory audit of bank transactions (at-least-once)."
    });
});

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI(c =>
{
    c.SwaggerEndpoint("/swagger/v1/swagger.json", "Audit API v1");
    c.RoutePrefix = "swagger";
});

app.MapControllers();

app.Run();
