using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using Confluent.Kafka;
using EBankingSerializationAPI.Models;
using EBankingSerializationAPI.Serializers;

namespace EBankingSerializationAPI.Services;

/// <summary>
/// Kafka producer service demonstrating typed serialization with validation.
/// Uses custom ISerializer&lt;Transaction&gt; to validate messages BEFORE sending to Kafka.
/// </summary>
public class SerializationProducerService : IDisposable
{
    private readonly IProducer<string, Transaction> _typedProducer;
    private readonly IProducer<string, string> _rawProducer;
    private readonly ILogger<SerializationProducerService> _logger;
    private readonly string _topic;

    // Metrics
    private long _v1Produced;
    private long _v2Produced;
    private long _validationErrors;
    private long _serializationErrors;
    private readonly ConcurrentBag<ProducedMessageInfo> _recentMessages = new();

    public SerializationProducerService(
        IConfiguration config,
        ILogger<SerializationProducerService> logger)
    {
        _logger = logger;
        _topic = config["Kafka:Topic"] ?? "banking.transactions";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = config["Kafka:BootstrapServers"] ?? "localhost:9092",
            ClientId = "ebanking-serialization-producer",
            Acks = Acks.All,
            MessageSendMaxRetries = 3,
            RetryBackoffMs = 1000
        };

        // Typed producer with custom serializer (validates before sending)
        _typedProducer = new ProducerBuilder<string, Transaction>(producerConfig)
            .SetValueSerializer(new TransactionJsonSerializer())
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Producer error: {Code} - {Reason}", e.Code, e.Reason);
            })
            .Build();

        // Raw string producer for v2 schema evolution demo
        _rawProducer = new ProducerBuilder<string, string>(producerConfig).Build();
    }

    /// <summary>
    /// Send a v1 transaction using the typed serializer (with validation).
    /// Invalid transactions are rejected BEFORE reaching Kafka.
    /// </summary>
    public async Task<ProduceResultDto> SendTransactionV1Async(Transaction tx)
    {
        try
        {
            var result = await _typedProducer.ProduceAsync(_topic, new Message<string, Transaction>
            {
                Key = tx.CustomerId,
                Value = tx,
                Headers = new Headers
                {
                    { "schema-version", Encoding.UTF8.GetBytes("1") },
                    { "serializer", Encoding.UTF8.GetBytes("TransactionJsonSerializer") },
                    { "source", Encoding.UTF8.GetBytes("ebanking-serialization-api") }
                }
            });

            Interlocked.Increment(ref _v1Produced);

            var info = new ProducedMessageInfo
            {
                TransactionId = tx.TransactionId,
                SchemaVersion = 1,
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                Timestamp = result.Timestamp.UtcDateTime
            };
            _recentMessages.Add(info);

            _logger.LogInformation(
                "v1 Transaction {TxId} → P{Partition}:O{Offset} (typed serializer, validated)",
                tx.TransactionId, result.Partition.Value, result.Offset.Value);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Produced",
                SchemaVersion = 1,
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                SerializerUsed = "TransactionJsonSerializer (validated)"
            };
        }
        catch (ArgumentException ex)
        {
            // Validation error from the serializer — message was NOT sent to Kafka
            Interlocked.Increment(ref _validationErrors);
            _logger.LogWarning("Validation rejected {TxId}: {Error}", tx.TransactionId, ex.Message);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "RejectedByValidation",
                ErrorMessage = ex.Message,
                SchemaVersion = 1,
                SerializerUsed = "TransactionJsonSerializer (validated)"
            };
        }
        catch (ProduceException<string, Transaction> ex)
        {
            Interlocked.Increment(ref _serializationErrors);
            _logger.LogError(ex, "Produce failed for {TxId}", tx.TransactionId);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Failed",
                ErrorMessage = ex.Error.Reason,
                SchemaVersion = 1
            };
        }
    }

    /// <summary>
    /// Send a v2 transaction (with riskScore) to demonstrate schema evolution.
    /// Uses raw string producer so the consumer can test BACKWARD compatibility.
    /// </summary>
    public async Task<ProduceResultDto> SendTransactionV2Async(TransactionV2 tx)
    {
        try
        {
            // Validate manually (same rules as v1 + v2-specific)
            if (string.IsNullOrWhiteSpace(tx.TransactionId))
                throw new ArgumentException("TransactionId is required");
            if (tx.Amount <= 0)
                throw new ArgumentException($"Amount must be > 0 (got {tx.Amount})");
            if (tx.RiskScore.HasValue && (tx.RiskScore < 0 || tx.RiskScore > 1))
                throw new ArgumentException($"RiskScore must be between 0 and 1 (got {tx.RiskScore})");

            var json = JsonSerializer.Serialize(tx, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            var result = await _rawProducer.ProduceAsync(_topic, new Message<string, string>
            {
                Key = tx.CustomerId,
                Value = json,
                Headers = new Headers
                {
                    { "schema-version", Encoding.UTF8.GetBytes("2") },
                    { "serializer", Encoding.UTF8.GetBytes("JsonSerializer (v2)") },
                    { "source", Encoding.UTF8.GetBytes("ebanking-serialization-api") }
                }
            });

            Interlocked.Increment(ref _v2Produced);

            var info = new ProducedMessageInfo
            {
                TransactionId = tx.TransactionId,
                SchemaVersion = 2,
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                Timestamp = result.Timestamp.UtcDateTime,
                HasRiskScore = tx.RiskScore.HasValue
            };
            _recentMessages.Add(info);

            _logger.LogInformation(
                "v2 Transaction {TxId} → P{Partition}:O{Offset} (riskScore={Risk})",
                tx.TransactionId, result.Partition.Value, result.Offset.Value, tx.RiskScore);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Produced",
                SchemaVersion = 2,
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                SerializerUsed = "JsonSerializer (v2 with riskScore)"
            };
        }
        catch (ArgumentException ex)
        {
            Interlocked.Increment(ref _validationErrors);
            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "RejectedByValidation",
                ErrorMessage = ex.Message,
                SchemaVersion = 2
            };
        }
    }

    public SerializationMetrics GetMetrics() => new()
    {
        V1MessagesProduced = Interlocked.Read(ref _v1Produced),
        V2MessagesProduced = Interlocked.Read(ref _v2Produced),
        ValidationErrors = Interlocked.Read(ref _validationErrors),
        SerializationErrors = Interlocked.Read(ref _serializationErrors),
        RecentMessages = _recentMessages.OrderByDescending(m => m.Timestamp).Take(20).ToList()
    };

    public void Dispose()
    {
        _typedProducer?.Flush(TimeSpan.FromSeconds(10));
        _typedProducer?.Dispose();
        _rawProducer?.Flush(TimeSpan.FromSeconds(10));
        _rawProducer?.Dispose();
    }
}

// ── DTOs ──────────────────────────────────────────────────────

public class ProduceResultDto
{
    public string TransactionId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int SchemaVersion { get; set; }
    public int Partition { get; set; }
    public long Offset { get; set; }
    public string? ErrorMessage { get; set; }
    public string? SerializerUsed { get; set; }
}

public class ProducedMessageInfo
{
    public string TransactionId { get; set; } = string.Empty;
    public int SchemaVersion { get; set; }
    public int Partition { get; set; }
    public long Offset { get; set; }
    public DateTime Timestamp { get; set; }
    public bool HasRiskScore { get; set; }
}

public class SerializationMetrics
{
    public long V1MessagesProduced { get; set; }
    public long V2MessagesProduced { get; set; }
    public long ValidationErrors { get; set; }
    public long SerializationErrors { get; set; }
    public List<ProducedMessageInfo> RecentMessages { get; set; } = new();
}
