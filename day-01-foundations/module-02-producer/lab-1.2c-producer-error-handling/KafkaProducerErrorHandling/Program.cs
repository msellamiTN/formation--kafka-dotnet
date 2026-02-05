using Confluent.Kafka;
using Microsoft.Extensions.Logging;
using System.Text;
using System.Text.Json;

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
    ClientId = "dotnet-error-handling-producer",
    Acks = Acks.All,
    
    // ===== RETRY AUTOMATIQUE =====
    MessageSendMaxRetries = 3,      // 3 tentatives
    RetryBackoffMs = 1000,          // 1 seconde entre retries
    RequestTimeoutMs = 30000,       // 30 secondes timeout
};

// ===== CRÉATION DU PRODUCER PRINCIPAL =====
using var producer = new ProducerBuilder<string, string>(config)
    .SetErrorHandler((_, error) =>
    {
        if (error.IsFatal)
        {
            logger.LogCritical("Fatal Kafka error: Code={Code}, Reason={Reason}. Producer cannot continue.",
                error.Code, error.Reason);
            Environment.Exit(1);
        }
        else
        {
            logger.LogWarning("Non-fatal Kafka error: Code={Code}, Reason={Reason}. Will retry if retriable.",
                error.Code, error.Reason);
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

// ===== CRÉATION DU PRODUCER DLQ =====
using var dlqProducer = new ProducerBuilder<string, string>(new ProducerConfig
{
    BootstrapServers = config.BootstrapServers,
    ClientId = "dlq-producer",
    Acks = Acks.All
}).Build();

logger.LogInformation("Producer started. Connecting to {Brokers}", config.BootstrapServers);

const string topicName = "orders.created";
const string dlqTopicName = "orders.dlq";

// Simuler 5 clients différents
var customers = new[] { "customer-A", "customer-B", "customer-C", "customer-D", "customer-E" };

try
{
    for (int i = 1; i <= 10; i++)
    {
        var customerId = customers[i % 5];
        var orderId = $"ORD-{customerId}-{i:D4}";
        var messageValue = $"{{\"orderId\": \"{orderId}\", \"customerId\": \"{customerId}\", \"amount\": {100 + i * 10}}}";
        
        logger.LogInformation("Sending message {Index}: {OrderId} for {CustomerId}", i, orderId, customerId);
        
        var message = new Message<string, string>
        {
            Key = customerId,
            Value = messageValue,
            Headers = new Headers
            {
                { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                { "source", Encoding.UTF8.GetBytes("dotnet-producer") }
            }
        };
        
        try
        {
            var deliveryResult = await producer.ProduceAsync(topicName, message);
            
            logger.LogInformation(
                "✓ Message {Index} delivered → Key: {Key}, Partition: {Partition}, Offset: {Offset}",
                i,
                customerId,
                deliveryResult.Partition.Value,
                deliveryResult.Offset.Value
            );
        }
        catch (ProduceException<string, string> ex)
        {
            logger.LogError(ex, 
                "Failed to produce message after {Retries} retries. ErrorCode: {ErrorCode}, Reason: {Reason}",
                config.MessageSendMaxRetries, ex.Error.Code, ex.Error.Reason
            );
            
            // Classification de l'erreur
            if (IsRetriableError(ex.Error.Code))
            {
                logger.LogWarning("Transient error persisted. Consider increasing retry count or timeout.");
            }
            else if (IsPermanentError(ex.Error.Code))
            {
                logger.LogError("Permanent error detected. Sending to DLQ.");
                await SendToDeadLetterQueueAsync(message, ex, dlqProducer, dlqTopicName);
            }
            else
            {
                logger.LogError("Configuration or unexpected error. Sending to DLQ.");
                await SendToDeadLetterQueueAsync(message, ex, dlqProducer, dlqTopicName);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unexpected error during message production");
            await SendToDeadLetterQueueAsync(message, ex, dlqProducer, dlqTopicName);
        }
        
        await Task.Delay(500);
    }
    
    logger.LogInformation("\n=== Summary ===");
    logger.LogInformation("All messages processed!");
}
catch (Exception ex)
{
    logger.LogCritical(ex, "Critical error in producer main loop");
}
finally
{
    logger.LogInformation("Flushing pending messages...");
    producer.Flush(TimeSpan.FromSeconds(10));
    dlqProducer.Flush(TimeSpan.FromSeconds(10));
    logger.LogInformation("Producer closed gracefully.");
}

// ===== HELPER METHODS =====

static bool IsRetriableError(ErrorCode errorCode)
{
    return errorCode switch
    {
        ErrorCode.Local_Transport => true,
        ErrorCode.Local_MsgTimedOut => true,
        ErrorCode.Local_QueueFull => true,
        ErrorCode.NotEnoughReplicas => true,
        ErrorCode.LeaderNotAvailable => true,
        ErrorCode.RequestTimedOut => true,
        _ => false
    };
}

static bool IsPermanentError(ErrorCode errorCode)
{
    return errorCode switch
    {
        ErrorCode.MsgSizeTooLarge => true,
        ErrorCode.InvalidTopic => true,
        ErrorCode.UnknownTopicOrPartition => true,
        ErrorCode.RecordTooLarge => true,
        ErrorCode.InvalidRequiredAcks => true,
        _ => false
    };
}

static async Task SendToDeadLetterQueueAsync(
    Message<string, string> failedMessage,
    Exception originalException,
    IProducer<string, string> dlqProducer,
    string dlqTopicName)
{
    var logger = LoggerFactory.Create(b => b.AddConsole()).CreateLogger("DLQ");
    
    var dlqMessage = new Message<string, string>
    {
        Key = failedMessage.Key,
        Value = failedMessage.Value,
        Headers = new Headers
        {
            // Métadonnées pour debugging
            { "original-topic", Encoding.UTF8.GetBytes("orders.created") },
            { "error-timestamp", Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) },
            { "error-type", Encoding.UTF8.GetBytes(originalException.GetType().Name) },
            { "error-message", Encoding.UTF8.GetBytes(originalException.Message) },
            { "retry-count", Encoding.UTF8.GetBytes("3") },
            { "correlation-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) }
        }
    };
    
    // Copier les headers originaux
    if (failedMessage.Headers != null)
    {
        foreach (var header in failedMessage.Headers)
        {
            if (!dlqMessage.Headers.Any(h => h.Key == header.Key))
            {
                dlqMessage.Headers.Add(header.Key, header.GetValueBytes());
            }
        }
    }
    
    try
    {
        await dlqProducer.ProduceAsync(dlqTopicName, dlqMessage);
        logger.LogWarning("Message sent to DLQ: Key={Key}", failedMessage.Key);
    }
    catch (Exception dlqEx)
    {
        // Si DLQ échoue aussi, logger dans fichier ou DB
        logger.LogCritical(dlqEx, "Failed to send message to DLQ. Message lost: Key={Key}", failedMessage.Key);
        
        // En production : écrire dans fichier local ou base de données
        await WriteToLocalFailureLogAsync(failedMessage, originalException, dlqEx);
    }
}

static async Task WriteToLocalFailureLogAsync(
    Message<string, string> message,
    Exception error1,
    Exception error2)
{
    var logger = LoggerFactory.Create(b => b.AddConsole()).CreateLogger("FailureLog");
    
    var logEntry = new
    {
        Timestamp = DateTime.UtcNow,
        Key = message.Key,
        Value = message.Value,
        OriginalError = error1.ToString(),
        DlqError = error2.ToString()
    };
    
    try
    {
        var logDir = Path.Combine(Path.GetTempPath(), "kafka-failures");
        Directory.CreateDirectory(logDir);
        
        var logFile = Path.Combine(logDir, $"{DateTime.UtcNow:yyyyMMdd}.log");
        await File.AppendAllTextAsync(logFile,
            JsonSerializer.Serialize(logEntry) + Environment.NewLine
        );
        
        logger.LogWarning("Message logged to local file: {LogFile}", logFile);
    }
    catch (Exception ex)
    {
        logger.LogCritical(ex, "Failed to write to local failure log. Message completely lost.");
    }
}
