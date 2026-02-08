using EBankingBalanceAPI.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSingleton<BalanceConsumerService>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<BalanceConsumerService>());

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new()
    {
        Title = "E-Banking Balance API",
        Version = "v1",
        Description = "Consumer Group Kafka pour le calcul de solde en temps réel"
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
