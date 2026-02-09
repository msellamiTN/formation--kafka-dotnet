using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using Confluent.Kafka;
using EBankingSerializationAPI.Models;
using EBankingSerializationAPI.Serializers;

namespace EBankingSerializationAPI.Services;

/// <summary>
/// Background consumer that reads messages from banking.transactions using
/// the typed deserializer. Demonstrates BACKWARD/FORWARD schema compatibility:
/// - v1 consumer reads v2 messages (extra fields ignored) → BACKWARD ✅
/// - v2 consumer reads v1 messages (missing fields get defaults) → FORWARD ✅
/// </summary>
public class SchemaEvolutionConsumerService : BackgroundService
{
    private readonly ILogger<SchemaEvolutionConsumerService> _logger;
    private readonly IConfiguration _configuration;

    // Store consumed messages for API access
    private readonly ConcurrentBag<ConsumedMessageInfo> _consumedMessages = new();

    // Metrics
    private long _messagesConsumed;
    private long _v1Messages;
    private long _v2Messages;
    private long _deserializationErrors;
    private string _status = "Starting";

    public SchemaEvolutionConsumerService(
        ILogger<SchemaEvolutionConsumerService> logger,
        IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _status = "Running";

        var bootstrapServers = _configuration["Kafka:BootstrapServers"] ?? "localhost:9092";
        var topic = _configuration["Kafka:Topic"] ?? "banking.transactions";
        var groupId = _configuration["Kafka:GroupId"] ?? "serialization-lab-consumer";

        var config = new ConsumerConfig
        {
            BootstrapServers = bootstrapServers,
            GroupId = groupId,
            ClientId = $"serialization-consumer-{Environment.MachineName}",
            AutoOffsetReset = AutoOffsetReset.Latest,
            EnableAutoCommit = true,
            AutoCommitIntervalMs = 5000,
            SessionTimeoutMs = 10000,
            HeartbeatIntervalMs = 3000
        };

        _logger.LogInformation(
            "Starting schema evolution consumer. Group: {Group}, Topic: {Topic}",
            groupId, topic);

        // Use typed deserializer (v1) — demonstrates BACKWARD compatibility
        using var consumer = new ConsumerBuilder<string, Transaction>(config)
            .SetValueDeserializer(new TransactionJsonDeserializer())
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Consumer error: {Code} - {Reason}", e.Code, e.Reason);
                if (e.IsFatal) _status = "Fatal Error";
            })
            .SetPartitionsAssignedHandler((c, partitions) =>
            {
                _logger.LogInformation("Partitions assigned: [{Partitions}]",
                    string.Join(", ", partitions.Select(p => p.Partition.Value)));
                _status = "Consuming";
            })
            .Build();

        consumer.Subscribe(topic);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var result = consumer.Consume(stoppingToken);
                    if (result == null) continue;

                    Interlocked.Increment(ref _messagesConsumed);

                    // Extract schema version from headers
                    var schemaVersion = "unknown";
                    if (result.Message.Headers != null)
                    {
                        var header = result.Message.Headers.FirstOrDefault(h => h.Key == "schema-version");
                        if (header != null)
                            schemaVersion = Encoding.UTF8.GetString(header.GetValueBytes());
                    }

                    if (schemaVersion == "2")
                        Interlocked.Increment(ref _v2Messages);
                    else
                        Interlocked.Increment(ref _v1Messages);

                    var tx = result.Message.Value;
                    var info = new ConsumedMessageInfo
                    {
                        TransactionId = tx.TransactionId,
                        CustomerId = tx.CustomerId,
                        Amount = tx.Amount,
                        Currency = tx.Currency,
                        SchemaVersion = schemaVersion,
                        Partition = result.Partition.Value,
                        Offset = result.Offset.Value,
                        ConsumedAt = DateTime.UtcNow,
                        DeserializerUsed = "TransactionJsonDeserializer (v1)",
                        BackwardCompatible = schemaVersion == "2"
                            ? "YES — v2 message read by v1 deserializer (extra fields ignored)"
                            : "N/A — same schema version"
                    };

                    _consumedMessages.Add(info);

                    _logger.LogInformation(
                        "Consumed {TxId} (schema-v{Version}) | {Amount} {Currency} | P{Partition}:O{Offset}{Compat}",
                        tx.TransactionId, schemaVersion, tx.Amount, tx.Currency,
                        result.Partition.Value, result.Offset.Value,
                        schemaVersion == "2" ? " | BACKWARD compat ✅" : "");
                }
                catch (ConsumeException ex)
                {
                    Interlocked.Increment(ref _deserializationErrors);
                    _logger.LogError("Deserialization error: {Reason}", ex.Error.Reason);
                }
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Consumer shutdown requested");
        }
        finally
        {
            _status = "Stopped";
            consumer.Close();
        }
    }

    // Public accessors for API

    public IReadOnlyList<ConsumedMessageInfo> GetConsumedMessages() =>
        _consumedMessages.OrderByDescending(m => m.ConsumedAt).Take(50).ToList().AsReadOnly();

    public ConsumerMetrics GetMetrics() => new()
    {
        TotalConsumed = Interlocked.Read(ref _messagesConsumed),
        V1Messages = Interlocked.Read(ref _v1Messages),
        V2Messages = Interlocked.Read(ref _v2Messages),
        DeserializationErrors = Interlocked.Read(ref _deserializationErrors),
        Status = _status
    };
}

// ── DTOs ──────────────────────────────────────────────────────

public class ConsumedMessageInfo
{
    public string TransactionId { get; set; } = string.Empty;
    public string CustomerId { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = string.Empty;
    public string SchemaVersion { get; set; } = string.Empty;
    public int Partition { get; set; }
    public long Offset { get; set; }
    public DateTime ConsumedAt { get; set; }
    public string DeserializerUsed { get; set; } = string.Empty;
    public string BackwardCompatible { get; set; } = string.Empty;
}

public class ConsumerMetrics
{
    public long TotalConsumed { get; set; }
    public long V1Messages { get; set; }
    public long V2Messages { get; set; }
    public long DeserializationErrors { get; set; }
    public string Status { get; set; } = string.Empty;
}
