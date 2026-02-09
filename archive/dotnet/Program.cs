using Confluent.Kafka;
using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// ═══════════════════════════════════════════════════════════════
// CONFIGURATION VIA ENVIRONMENT VARIABLES
// ═══════════════════════════════════════════════════════════════
var bootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") ?? "localhost:9092";
var topic = Environment.GetEnvironmentVariable("KAFKA_TOPIC") ?? "orders";
var groupId = Environment.GetEnvironmentVariable("KAFKA_GROUP_ID") ?? "orders-consumer-group";
var autoOffsetReset = Environment.GetEnvironmentVariable("KAFKA_AUTO_OFFSET_RESET") ?? "earliest";
var dltTopic = Environment.GetEnvironmentVariable("KAFKA_DLT_TOPIC") ?? "orders.DLT";
var maxRetries = int.Parse(Environment.GetEnvironmentVariable("MAX_RETRIES") ?? "3");
var retryBackoffMs = int.Parse(Environment.GetEnvironmentVariable("RETRY_BACKOFF_MS") ?? "1000");

var consumerConfig = new ConsumerConfig
{
    BootstrapServers = bootstrapServers,
    GroupId = groupId,
    AutoOffsetReset = Enum.Parse<AutoOffsetReset>(autoOffsetReset, true),
    EnableAutoCommit = false,
    EnableAutoOffsetStore = false,  // Explicit offset control: call StoreOffset() only after successful processing
    SessionTimeoutMs = 45000,
    HeartbeatIntervalMs = 15000,
    MaxPollIntervalMs = 300000,
    PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
};

// ═══════════════════════════════════════════════════════════════
// CONSUMER STATE (monitoring)
// ═══════════════════════════════════════════════════════════════
var messagesProcessed = 0L;
var messagesRetried = 0L;
var messagesSentToDlt = 0L;
var processingErrors = 0L;
var partitionsAssigned = new List<string>();
var lastRebalanceTime = DateTime.MinValue;
var rebalanceCount = 0;
var dltMessages = new ConcurrentBag<object>();
var cts = new CancellationTokenSource();

// ═══════════════════════════════════════════════════════════════
// DLT PRODUCER
// ═══════════════════════════════════════════════════════════════
var dltProducer = new ProducerBuilder<string, string>(new ProducerConfig
{
    BootstrapServers = bootstrapServers,
    ClientId = "m04-dlt-producer",
    Acks = Acks.All
}).Build();

Task.Run(() => ConsumeMessages(cts.Token));

var app = builder.Build();

// ═══════════════════════════════════════════════════════════════
// ENDPOINTS REST API
// ═══════════════════════════════════════════════════════════════
app.MapGet("/health", () => Results.Ok(new { status = "UP" }));

app.MapGet("/api/v1/stats", () => Results.Ok(new
{
    messagesProcessed,
    messagesRetried,
    messagesSentToDlt,
    processingErrors,
    partitionsAssigned,
    rebalanceCount,
    lastRebalanceTime = lastRebalanceTime == DateTime.MinValue ? "N/A" : lastRebalanceTime.ToString("O")
}));

app.MapGet("/api/v1/partitions", () => Results.Ok(new
{
    partitions = partitionsAssigned,
    count = partitionsAssigned.Count
}));

app.MapGet("/api/v1/dlt/count", () => Results.Ok(new
{
    dltTopic,
    count = Interlocked.Read(ref messagesSentToDlt)
}));

app.MapGet("/api/v1/dlt/messages", () => Results.Ok(new
{
    count = dltMessages.Count,
    messages = dltMessages.ToArray()
}));

app.Run();

// ═══════════════════════════════════════════════════════════════
// CONSUME LOOP WITH DLT AND RETRY
// ═══════════════════════════════════════════════════════════════
async Task ConsumeMessages(CancellationToken cancellationToken)
{
    using var consumer = new ConsumerBuilder<string, string>(consumerConfig)
        .SetPartitionsAssignedHandler((c, partitions) =>
        {
            rebalanceCount++;
            lastRebalanceTime = DateTime.UtcNow;
            partitionsAssigned = partitions.Select(p => $"{p.Topic}-{p.Partition}").ToList();
            Console.WriteLine($"[REBALANCE] Partitions assigned: {string.Join(", ", partitionsAssigned)}");
        })
        .SetPartitionsRevokedHandler((c, partitions) =>
        {
            var revoked = partitions.Select(p => $"{p.Topic}-{p.Partition}").ToList();
            Console.WriteLine($"[REBALANCE] Partitions revoked: {string.Join(", ", revoked)}");
            try
            {
                c.Commit();
                Console.WriteLine("[REBALANCE] Offsets committed before revocation");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[REBALANCE] Error committing offsets: {ex.Message}");
            }
        })
        .SetPartitionsLostHandler((c, partitions) =>
        {
            var lost = partitions.Select(p => $"{p.Topic}-{p.Partition}").ToList();
            Console.WriteLine($"[REBALANCE] Partitions lost: {string.Join(", ", lost)}");
        })
        .Build();

    consumer.Subscribe(topic);
    Console.WriteLine($"[CONSUMER] Subscribed to topic: {topic}");
    Console.WriteLine($"[CONSUMER] Group ID: {groupId}");
    Console.WriteLine($"[CONSUMER] Bootstrap servers: {bootstrapServers}");
    Console.WriteLine($"[CONSUMER] DLT topic: {dltTopic}");
    Console.WriteLine($"[CONSUMER] Max retries: {maxRetries}, Backoff: {retryBackoffMs}ms");

    while (!cancellationToken.IsCancellationRequested)
    {
        try
        {
            var consumeResult = consumer.Consume(TimeSpan.FromMilliseconds(1000));
            
            if (consumeResult == null) continue;

            Console.WriteLine($"[MESSAGE] Key: {consumeResult.Message.Key}, " +
                            $"Partition: {consumeResult.Partition}, " +
                            $"Offset: {consumeResult.Offset}");

            var success = await ProcessWithRetryAsync(consumeResult, cancellationToken);

            // StoreOffset() marks this offset for the next Commit()
            // Only store AFTER processing (success or DLT) to avoid data loss
            consumer.StoreOffset(consumeResult);
            consumer.Commit(consumeResult);
            Interlocked.Increment(ref messagesProcessed);
        }
        catch (ConsumeException ex)
        {
            Console.WriteLine($"[ERROR] Consume error: {ex.Error.Reason}");
            Interlocked.Increment(ref processingErrors);
        }
        catch (OperationCanceledException)
        {
            break;
        }
    }

    consumer.Close();
    dltProducer.Dispose();
}

// ═══════════════════════════════════════════════════════════════
// PROCESSING WITH RETRY AND DLT
// Exponential backoff + jitter, DLT for permanent errors
// ═══════════════════════════════════════════════════════════════
async Task<bool> ProcessWithRetryAsync(ConsumeResult<string, string> result, CancellationToken ct)
{
    for (int attempt = 1; attempt <= maxRetries; attempt++)
    {
        try
        {
            await ProcessRecordAsync(result, ct);
            return true;
        }
        catch (Exception ex) when (IsTransient(ex) && attempt < maxRetries)
        {
            Interlocked.Increment(ref messagesRetried);
            var baseDelay = TimeSpan.FromMilliseconds(retryBackoffMs * Math.Pow(2, attempt - 1));
            var jitter = TimeSpan.FromMilliseconds(Random.Shared.Next(0, (int)(baseDelay.TotalMilliseconds * 0.2)));
            var delay = baseDelay + jitter;

            Console.WriteLine($"[RETRY] Attempt {attempt}/{maxRetries} for P{result.Partition}:O{result.Offset} " +
                            $"— retrying in {delay.TotalMilliseconds:F0}ms: {ex.Message}");
            await Task.Delay(delay, ct);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[ERROR] Non-retryable error for P{result.Partition}:O{result.Offset}: {ex.Message}");
            await SendToDltAsync(result, ex.Message, attempt);
            return false;
        }
    }

    // Max retries exhausted
    Console.WriteLine($"[DLT] Max retries ({maxRetries}) exhausted for P{result.Partition}:O{result.Offset}");
    await SendToDltAsync(result, "Max retries exceeded", maxRetries);
    return false;
}

// ═══════════════════════════════════════════════════════════════
// BUSINESS PROCESSING
// Simulates processing with validation
// ═══════════════════════════════════════════════════════════════
async Task ProcessRecordAsync(ConsumeResult<string, string> result, CancellationToken ct)
{
    // Validate JSON
    if (string.IsNullOrWhiteSpace(result.Message.Value))
        throw new InvalidOperationException("Empty message value");

    try
    {
        using var doc = JsonDocument.Parse(result.Message.Value);
        var root = doc.RootElement;

        // Validate amount (non-retryable if negative)
        if (root.TryGetProperty("amount", out var amountProp))
        {
            var amount = amountProp.GetDouble();
            if (amount < 0)
                throw new InvalidOperationException($"Validation failed: negative amount ({amount})");
        }
    }
    catch (JsonException ex)
    {
        throw new InvalidOperationException($"Invalid JSON: {ex.Message}");
    }

    // Simulate processing
    await Task.Delay(100, ct);
}

// ═══════════════════════════════════════════════════════════════
// SEND TO DEAD LETTER TOPIC
// ═══════════════════════════════════════════════════════════════
async Task SendToDltAsync(ConsumeResult<string, string> failedMessage, string errorReason, int attempts)
{
    try
    {
        var dltMsg = new Message<string, string>
        {
            Key = failedMessage.Message.Key,
            Value = failedMessage.Message.Value,
            Headers = new Headers
            {
                { "original-topic", Encoding.UTF8.GetBytes(failedMessage.Topic) },
                { "original-partition", Encoding.UTF8.GetBytes(failedMessage.Partition.Value.ToString()) },
                { "original-offset", Encoding.UTF8.GetBytes(failedMessage.Offset.Value.ToString()) },
                { "error-reason", Encoding.UTF8.GetBytes(errorReason) },
                { "retry-count", Encoding.UTF8.GetBytes(attempts.ToString()) },
                { "consumer-group", Encoding.UTF8.GetBytes(groupId) },
                { "failed-at", Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) }
            }
        };

        await dltProducer.ProduceAsync(dltTopic, dltMsg);
        Interlocked.Increment(ref messagesSentToDlt);

        dltMessages.Add(new
        {
            key = failedMessage.Message.Key,
            originalPartition = failedMessage.Partition.Value,
            originalOffset = failedMessage.Offset.Value,
            errorReason,
            attempts,
            failedAt = DateTime.UtcNow
        });

        Console.WriteLine($"[DLT] Sent to {dltTopic}: Key={failedMessage.Message.Key} | " +
                        $"P{failedMessage.Partition}:O{failedMessage.Offset} | Reason: {errorReason}");
    }
    catch (Exception ex)
    {
        Interlocked.Increment(ref processingErrors);
        Console.WriteLine($"[ERROR] Failed to send to DLT: {ex.Message}");
    }
}

// ═══════════════════════════════════════════════════════════════
// ERROR CLASSIFICATION
// Transient → retry, Non-transient → DLT immediately
// ═══════════════════════════════════════════════════════════════
bool IsTransient(Exception ex) => ex is TimeoutException
    or OperationCanceledException
    or KafkaException { Error.IsFatal: false };
