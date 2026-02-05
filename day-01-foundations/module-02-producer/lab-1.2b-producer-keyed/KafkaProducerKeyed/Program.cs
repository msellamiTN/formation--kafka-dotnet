using Confluent.Kafka;
using Microsoft.Extensions.Logging;

// ===== CONFIGURATION =====
var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Information);
});
var logger = loggerFactory.CreateLogger<Program>();

var config = new ProducerConfig
{
    BootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") 
                       ?? "localhost:9092",
    ClientId = "dotnet-keyed-producer",
    Acks = Acks.All
};

// ===== CRÉATION DU PRODUCER =====
// <string, string> = <Type de la clé, Type de la valeur>
using var producer = new ProducerBuilder<string, string>(config)
    .SetErrorHandler((_, e) => logger.LogError("Error: {Reason}", e.Reason))
    .Build();

logger.LogInformation("Producer started. Connecting to {Brokers}", config.BootstrapServers);

const string topicName = "orders.created";

// Simuler 5 clients différents
var customers = new[] { "customer-A", "customer-B", "customer-C", "customer-D", "customer-E" };

try
{
    for (int i = 1; i <= 30; i++)
    {
        // Chaque client a plusieurs commandes
        var customerId = customers[i % 5];
        var orderId = $"ORD-{customerId}-{i:D4}";
        var messageValue = $"{{\"orderId\": \"{orderId}\", \"customerId\": \"{customerId}\", \"amount\": {100 + i * 10}}}";
        
        logger.LogInformation("Sending order {OrderId} for customer {CustomerId}", orderId, customerId);
        
        var deliveryResult = await producer.ProduceAsync(topicName, new Message<string, string>
        {
            Key = customerId,  // LA CLÉ DÉTERMINE LA PARTITION
            Value = messageValue,
            Timestamp = Timestamp.Default  // Utiliser timestamp actuel
        });
        
        logger.LogInformation(
            "✓ Delivered → Key: {Key}, Partition: {Partition}, Offset: {Offset}",
            customerId,
            deliveryResult.Partition.Value,
            deliveryResult.Offset.Value
        );
        
        await Task.Delay(200);
    }
    
    logger.LogInformation("\n=== Summary ===");
    logger.LogInformation("All 30 messages sent successfully!");
    logger.LogInformation("Notice: All messages with the same key went to the same partition.");
}
catch (ProduceException<string, string> ex)
{
    logger.LogError(ex, "Failed to produce message");
}
finally
{
    producer.Flush(TimeSpan.FromSeconds(10));
    logger.LogInformation("Producer closed.");
}
