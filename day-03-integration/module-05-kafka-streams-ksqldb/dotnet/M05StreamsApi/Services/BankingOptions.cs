using Microsoft.Extensions.Configuration;

namespace M05StreamsApi.Services;

public sealed class BankingOptions
{
    public string BootstrapServers { get; init; } = "localhost:9092";
    public string ClientId { get; init; } = "m05-streams-api-dotnet";
    public string GroupId { get; init; } = "m05-streams-api-dotnet-banking";

    public string TransactionsTopic { get; init; } = "banking.transactions";
    public string BalancesTopic { get; init; } = "banking.balances";
    public string FraudAlertsTopic { get; init; } = "banking.fraud-alerts";
    public string DlqTopic { get; init; } = "banking.transactions.dlq";

    public static BankingOptions FromConfiguration(IConfiguration configuration)
    {
        var section = configuration.GetSection("Kafka");
        return new BankingOptions
        {
            BootstrapServers = section["BootstrapServers"] ?? "localhost:9092",
            ClientId = section["ClientId"] ?? "m05-streams-api-dotnet",
            GroupId = section["GroupId"] ?? "m05-streams-api-dotnet-banking",
            TransactionsTopic = section["TransactionsTopic"] ?? "banking.transactions",
            BalancesTopic = section["BalancesTopic"] ?? "banking.balances",
            FraudAlertsTopic = section["FraudAlertsTopic"] ?? "banking.fraud-alerts",
            DlqTopic = section["DlqTopic"] ?? "banking.transactions.dlq"
        };
    }
}
