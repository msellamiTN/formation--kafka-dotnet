using Microsoft.Extensions.Configuration;

namespace M05StreamsApi.Services;

public sealed class StreamsOptions
{
    public string BootstrapServers { get; init; } = "localhost:9092";
    public string ClientId { get; init; } = "m05-streams-api-dotnet";
    public string GroupId { get; init; } = "m05-streams-api-dotnet";

    public string InputTopic { get; init; } = "sales-events";
    public string OutputTopic { get; init; } = "sales-by-product";
    public string ProductsTopic { get; init; } = "products";

    public string LargeSalesTopic { get; init; } = "large-sales";
    public string SalesPerMinuteTopic { get; init; } = "sales-per-minute";
    public string EnrichedSalesTopic { get; init; } = "enriched-sales";

    public static StreamsOptions FromConfiguration(IConfiguration configuration)
    {
        var section = configuration.GetSection("Kafka");
        return new StreamsOptions
        {
            BootstrapServers = section["BootstrapServers"] ?? "localhost:9092",
            ClientId = section["ClientId"] ?? "m05-streams-api-dotnet",
            GroupId = section["GroupId"] ?? "m05-streams-api-dotnet",
            InputTopic = section["InputTopic"] ?? "sales-events",
            OutputTopic = section["OutputTopic"] ?? "sales-by-product",
            ProductsTopic = section["ProductsTopic"] ?? "products",
            LargeSalesTopic = section["LargeSalesTopic"] ?? "large-sales",
            SalesPerMinuteTopic = section["SalesPerMinuteTopic"] ?? "sales-per-minute",
            EnrichedSalesTopic = section["EnrichedSalesTopic"] ?? "enriched-sales"
        };
    }
}
