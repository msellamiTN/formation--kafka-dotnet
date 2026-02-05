using Confluent.Kafka;
using Microsoft.Extensions.Logging;
using System.Text;

// ===== CONFIGURATION =====
var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddConsole();
    builder.SetMinimumLevel(LogLevel.Information);
});
var logger = loggerFactory.CreateLogger<Program>();

var config = new ProducerConfig
{
    // Adresse du cluster Kafka
    // Docker: localhost:9092
    // OKD/K3s: bhf-kafka-kafka-bootstrap:9092
    BootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") 
                       ?? "localhost:9092",
    
    // Identification du client (pour logs et monitoring)
    ClientId = "dotnet-basic-producer",
    
    // Garantie de livraison : attendre confirmation de tous les ISR
    Acks = Acks.All,
    
    // Retry automatique en cas d'erreur retriable
    MessageSendMaxRetries = 3,
    RetryBackoffMs = 1000,
    RequestTimeoutMs = 30000
};

// ===== CRÉATION DU PRODUCER =====
using var producer = new ProducerBuilder<Null, string>(config)
    .SetErrorHandler((_, e) => 
    {
        logger.LogError("Producer error: Code={Code}, Reason={Reason}, IsFatal={IsFatal}", 
            e.Code, e.Reason, e.IsFatal);
        if (e.IsFatal)
        {
            logger.LogCritical("Fatal error detected. Exiting...");
            Environment.Exit(1);
        }
    })
    .SetLogHandler((_, logMessage) => 
    {
        var logLevel = logMessage.Level switch
        {
            SyslogLevel.Emergency or SyslogLevel.Alert or SyslogLevel.Critical => LogLevel.Critical,
            SyslogLevel.Error => LogLevel.Error,
            SyslogLevel.Warning => LogLevel.Warning,
            SyslogLevel.Notice or SyslogLevel.Info => LogLevel.Information,
            _ => LogLevel.Debug
        };
        logger.Log(logLevel, "Kafka internal log: {Message}", logMessage.Message);
    })
    .Build();

logger.LogInformation("Producer started. Connecting to {Brokers}", config.BootstrapServers);

// ===== ENVOI DE MESSAGES =====
const string topicName = "orders.created";

try
{
    for (int i = 1; i <= 10; i++)
    {
        var messageValue = $"{{\"orderId\": \"ORD-{i:D4}\", \"timestamp\": \"{DateTime.UtcNow:o}\", \"amount\": {100 + i * 10}}}";
        
        logger.LogInformation("Sending message {Index}: {Message}", i, messageValue);
        
        // ProduceAsync retourne une Task<DeliveryResult>
        var deliveryResult = await producer.ProduceAsync(topicName, new Message<Null, string>
        {
            Value = messageValue,
            // Headers optionnels (métadonnées)
            Headers = new Headers
            {
                { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                { "source", Encoding.UTF8.GetBytes("dotnet-producer") }
            }
        });
        
        // Confirmation de livraison
        logger.LogInformation(
            "✓ Message {Index} delivered → Topic: {Topic}, Partition: {Partition}, Offset: {Offset}, Timestamp: {Timestamp}",
            i,
            deliveryResult.Topic,
            deliveryResult.Partition.Value,
            deliveryResult.Offset.Value,
            deliveryResult.Timestamp.UtcDateTime
        );
        
        await Task.Delay(500);  // Pause 500ms entre chaque message
    }
    
    logger.LogInformation("All messages sent successfully!");
}
catch (ProduceException<Null, string> ex)
{
    logger.LogError(ex, "Failed to produce message");
    logger.LogError("Error Code: {ErrorCode}, Reason: {Reason}, IsFatal: {IsFatal}", 
        ex.Error.Code, ex.Error.Reason, ex.Error.IsFatal);
}
catch (Exception ex)
{
    logger.LogError(ex, "Unexpected error");
}
finally
{
    // IMPORTANT : Flush des messages en attente avant fermeture
    logger.LogInformation("Flushing pending messages...");
    producer.Flush(TimeSpan.FromSeconds(10));
    logger.LogInformation("Producer closed gracefully.");
}
