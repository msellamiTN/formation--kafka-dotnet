using EBankingAuditAPI.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<AuditConsumerService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<AuditConsumerService>());

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new()
    {
        Title = "E-Banking Audit & Compliance API",
        Version = "v1",
        Description = "Consumer Kafka avec manual commit pour l'audit réglementaire des transactions bancaires (at-least-once)"
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
