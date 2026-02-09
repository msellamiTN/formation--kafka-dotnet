using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using Confluent.Kafka;
using EBankingIdempotentProducerAPI.Models;

namespace EBankingIdempotentProducerAPI.Services;

/// <summary>
/// Kafka producer with EnableIdempotence = true.
/// Demonstrates PID (Producer ID) + sequence numbers for deduplication.
/// The broker assigns a unique PID on first connection and tracks sequence
/// numbers per partition to silently deduplicate retried messages.
/// </summary>
public class IdempotentProducerService : IDisposable
{
    private readonly IProducer<string, string> _producer;
    private readonly ILogger<IdempotentProducerService> _logger;
    private readonly string _topic;

    // Metrics
    private long _messagesProduced;
    private long _messagesFailed;
    private readonly ConcurrentBag<ProduceRecord> _recentMessages = new();
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public IdempotentProducerService(
        IConfiguration config,
        ILogger<IdempotentProducerService> logger)
    {
        _logger = logger;
        _topic = config["Kafka:Topic"] ?? "banking.transactions";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = config["Kafka:BootstrapServers"] ?? "localhost:9092",
            ClientId = "ebanking-idempotent-producer",

            // ═══ IDEMPOTENCE ENABLED ═══
            // This is the KEY setting for this lab.
            // When true, the broker assigns a PID and tracks sequence numbers
            // to deduplicate retried messages automatically.
            EnableIdempotence = true,

            // These are FORCED by EnableIdempotence = true:
            // - Acks = All (must wait for all ISR replicas)
            // - MaxInFlight <= 5 (to maintain ordering with retries)
            // - MessageSendMaxRetries = int.MaxValue (infinite retries)
            Acks = Acks.All,
            MaxInFlight = 5,
            MessageSendMaxRetries = int.MaxValue,

            // Performance tuning (same as Day 01 lab 1.2c)
            LingerMs = 10,
            BatchSize = 16384,
            CompressionType = CompressionType.Snappy,
            RetryBackoffMs = 100
        };

        _producer = new ProducerBuilder<string, string>(producerConfig)
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Idempotent producer error: {Code} - {Reason} (Fatal={Fatal})",
                    e.Code, e.Reason, e.IsFatal);
            })
            .SetLogHandler((_, log) =>
            {
                // Look for PID assignment in Kafka internal logs
                if (log.Message.Contains("PID") || log.Message.Contains("ProducerId"))
                {
                    _logger.LogInformation("IDEMPOTENCE: {Message}", log.Message);
                }
            })
            .Build();

        _logger.LogInformation(
            "Idempotent producer created. EnableIdempotence=true, Acks=All, MaxInFlight=5");
    }

    public async Task<ProduceResultDto> SendAsync(Transaction tx)
    {
        try
        {
            var json = JsonSerializer.Serialize(tx, _jsonOptions);

            var result = await _producer.ProduceAsync(_topic, new Message<string, string>
            {
                Key = tx.CustomerId,
                Value = json,
                Headers = new Headers
                {
                    { "producer-type", Encoding.UTF8.GetBytes("idempotent") },
                    { "enable-idempotence", Encoding.UTF8.GetBytes("true") },
                    { "source", Encoding.UTF8.GetBytes("ebanking-idempotent-api") }
                }
            });

            Interlocked.Increment(ref _messagesProduced);

            var record = new ProduceRecord
            {
                TransactionId = tx.TransactionId,
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                Timestamp = result.Timestamp.UtcDateTime,
                ProducerType = "idempotent"
            };
            _recentMessages.Add(record);

            _logger.LogInformation(
                "[IDEMPOTENT] {TxId} → P{Partition}:O{Offset}",
                tx.TransactionId, result.Partition.Value, result.Offset.Value);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Produced",
                ProducerType = "idempotent (EnableIdempotence=true)",
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                EnableIdempotence = true,
                AcksConfig = "All (forced by idempotence)"
            };
        }
        catch (ProduceException<string, string> ex)
        {
            Interlocked.Increment(ref _messagesFailed);
            _logger.LogError(ex, "[IDEMPOTENT] Failed {TxId}: {Error}",
                tx.TransactionId, ex.Error.Reason);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Failed",
                ProducerType = "idempotent",
                ErrorMessage = ex.Error.Reason,
                EnableIdempotence = true
            };
        }
    }

    public IdempotentProducerMetrics GetMetrics() => new()
    {
        EnableIdempotence = true,
        AcksConfig = "All (forced)",
        MaxInFlight = 5,
        MaxRetries = "int.MaxValue (forced)",
        MessagesProduced = Interlocked.Read(ref _messagesProduced),
        MessagesFailed = Interlocked.Read(ref _messagesFailed),
        RecentMessages = _recentMessages.OrderByDescending(m => m.Timestamp).Take(20).ToList()
    };

    public void Dispose()
    {
        _producer?.Flush(TimeSpan.FromSeconds(10));
        _producer?.Dispose();
    }
}

/// <summary>
/// Kafka producer WITHOUT idempotence (for side-by-side comparison).
/// Shows the risk: if a retry happens, the message may be written twice.
/// </summary>
public class NonIdempotentProducerService : IDisposable
{
    private readonly IProducer<string, string> _producer;
    private readonly ILogger<NonIdempotentProducerService> _logger;
    private readonly string _topic;

    private long _messagesProduced;
    private long _messagesFailed;
    private readonly ConcurrentBag<ProduceRecord> _recentMessages = new();
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public NonIdempotentProducerService(
        IConfiguration config,
        ILogger<NonIdempotentProducerService> logger)
    {
        _logger = logger;
        _topic = config["Kafka:Topic"] ?? "banking.transactions";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = config["Kafka:BootstrapServers"] ?? "localhost:9092",
            ClientId = "ebanking-non-idempotent-producer",

            // ═══ IDEMPOTENCE DISABLED ═══
            // Without idempotence, retries can create duplicates.
            EnableIdempotence = false,

            Acks = Acks.Leader,           // Only wait for leader (not all replicas)
            MaxInFlight = 5,
            MessageSendMaxRetries = 3,    // Limited retries
            RetryBackoffMs = 1000,

            LingerMs = 10,
            BatchSize = 16384,
            CompressionType = CompressionType.Snappy
        };

        _producer = new ProducerBuilder<string, string>(producerConfig)
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Non-idempotent producer error: {Code} - {Reason}", e.Code, e.Reason);
            })
            .Build();

        _logger.LogInformation(
            "Non-idempotent producer created. EnableIdempotence=false, Acks=Leader");
    }

    public async Task<ProduceResultDto> SendAsync(Transaction tx)
    {
        try
        {
            var json = JsonSerializer.Serialize(tx, _jsonOptions);

            var result = await _producer.ProduceAsync(_topic, new Message<string, string>
            {
                Key = tx.CustomerId,
                Value = json,
                Headers = new Headers
                {
                    { "producer-type", Encoding.UTF8.GetBytes("non-idempotent") },
                    { "enable-idempotence", Encoding.UTF8.GetBytes("false") },
                    { "source", Encoding.UTF8.GetBytes("ebanking-idempotent-api") }
                }
            });

            Interlocked.Increment(ref _messagesProduced);

            var record = new ProduceRecord
            {
                TransactionId = tx.TransactionId,
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                Timestamp = result.Timestamp.UtcDateTime,
                ProducerType = "non-idempotent"
            };
            _recentMessages.Add(record);

            _logger.LogInformation(
                "[NON-IDEMPOTENT] {TxId} → P{Partition}:O{Offset}",
                tx.TransactionId, result.Partition.Value, result.Offset.Value);

            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Produced",
                ProducerType = "non-idempotent (EnableIdempotence=false)",
                Partition = result.Partition.Value,
                Offset = result.Offset.Value,
                EnableIdempotence = false,
                AcksConfig = "Leader (not All — weaker guarantee)"
            };
        }
        catch (ProduceException<string, string> ex)
        {
            Interlocked.Increment(ref _messagesFailed);
            return new ProduceResultDto
            {
                TransactionId = tx.TransactionId,
                Status = "Failed",
                ProducerType = "non-idempotent",
                ErrorMessage = ex.Error.Reason,
                EnableIdempotence = false
            };
        }
    }

    public NonIdempotentProducerMetrics GetMetrics() => new()
    {
        EnableIdempotence = false,
        AcksConfig = "Leader",
        MaxInFlight = 5,
        MaxRetries = "3",
        MessagesProduced = Interlocked.Read(ref _messagesProduced),
        MessagesFailed = Interlocked.Read(ref _messagesFailed),
        DuplicateRisk = "YES — if a retry occurs after broker wrote but before ACK received",
        RecentMessages = _recentMessages.OrderByDescending(m => m.Timestamp).Take(20).ToList()
    };

    public void Dispose()
    {
        _producer?.Flush(TimeSpan.FromSeconds(10));
        _producer?.Dispose();
    }
}

// ── DTOs ──────────────────────────────────────────────────────

public class ProduceResultDto
{
    public string TransactionId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string ProducerType { get; set; } = string.Empty;
    public int Partition { get; set; }
    public long Offset { get; set; }
    public bool EnableIdempotence { get; set; }
    public string AcksConfig { get; set; } = string.Empty;
    public string? ErrorMessage { get; set; }
}

public class ProduceRecord
{
    public string TransactionId { get; set; } = string.Empty;
    public int Partition { get; set; }
    public long Offset { get; set; }
    public DateTime Timestamp { get; set; }
    public string ProducerType { get; set; } = string.Empty;
}

public class IdempotentProducerMetrics
{
    public bool EnableIdempotence { get; set; }
    public string AcksConfig { get; set; } = string.Empty;
    public int MaxInFlight { get; set; }
    public string MaxRetries { get; set; } = string.Empty;
    public long MessagesProduced { get; set; }
    public long MessagesFailed { get; set; }
    public List<ProduceRecord> RecentMessages { get; set; } = new();
}

public class NonIdempotentProducerMetrics
{
    public bool EnableIdempotence { get; set; }
    public string AcksConfig { get; set; } = string.Empty;
    public int MaxInFlight { get; set; }
    public string MaxRetries { get; set; } = string.Empty;
    public long MessagesProduced { get; set; }
    public long MessagesFailed { get; set; }
    public string DuplicateRisk { get; set; } = string.Empty;
    public List<ProduceRecord> RecentMessages { get; set; } = new();
}
