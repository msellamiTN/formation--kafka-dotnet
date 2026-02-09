using Confluent.Kafka;
using System.Text.Json;
using EBankingResilientProducerAPI.Models;

namespace EBankingResilientProducerAPI.Services;

public class ResilientKafkaProducerService : IDisposable
{
    private readonly IProducer<string, string> _producer;
    private readonly IProducer<string, string> _dlqProducer;
    private readonly ILogger<ResilientKafkaProducerService> _logger;
    private readonly string _topic;
    private readonly string _dlqTopic;

    // Circuit Breaker state
    private int _consecutiveFailures = 0;
    private DateTime _lastFailure = DateTime.MinValue;
    private const int CircuitBreakerThreshold = 5;
    private static readonly TimeSpan CircuitBreakerTimeout = TimeSpan.FromMinutes(1);

    // Metrics
    private long _messagesProduced = 0;
    private long _messagesFailed = 0;
    private long _messagesSentToDlq = 0;
    private long _messagesSavedToFile = 0;
    private readonly Dictionary<string, int> _errorCounts = new();

    public ResilientKafkaProducerService(IConfiguration config, ILogger<ResilientKafkaProducerService> logger)
    {
        _logger = logger;
        _topic = config["Kafka:Topic"] ?? "banking.transactions";
        _dlqTopic = config["Kafka:DlqTopic"] ?? "banking.transactions.dlq";

        // Sandbox-specific configuration (stability over high-guarantees)
        var producerConfig = new ProducerConfig
        {
            BootstrapServers = config["Kafka:BootstrapServers"] ?? "localhost:9092",
            ClientId = config["Kafka:ClientId"] ?? "ebanking-resilient-producer",
            Acks = Acks.Leader, // Changed from All for Sandbox stability
            EnableIdempotence = false, // Disabled for Sandbox stability
            MessageSendMaxRetries = 3,
            RetryBackoffMs = 1000,
            RequestTimeoutMs = 10000,
            LingerMs = 10,
            BatchSize = 16384,
            CompressionType = CompressionType.Snappy
        };

        _producer = new ProducerBuilder<string, string>(producerConfig)
            .SetErrorHandler((_, error) =>
            {
                if (error.IsFatal)
                    _logger.LogCritical("FATAL Kafka Error: {Reason}", error.Reason);
                else
                    _logger.LogWarning("Kafka Error: {Reason} (Code: {Code})", error.Reason, error.Code);
            })
            .Build();

        _dlqProducer = new ProducerBuilder<string, string>(producerConfig).Build();
    }

    /// <summary>
    /// Send transaction with full error handling, retry, DLQ, and circuit breaker
    /// </summary>
    public async Task<TransactionResult> SendTransactionAsync(
        Transaction transaction, CancellationToken ct = default)
    {
        // Circuit Breaker check
        if (IsCircuitOpen())
        {
            _logger.LogWarning("Circuit breaker OPEN. Sending {Id} directly to DLQ",
                transaction.TransactionId);
            await SendToDlqAsync(transaction, "Circuit breaker open", "CircuitBreakerException");
            return new TransactionResult
            {
                TransactionId = transaction.TransactionId,
                Status = "SentToDLQ",
                ErrorMessage = "Circuit breaker is open - too many consecutive failures"
            };
        }

        // Retry with exponential backoff
        var maxRetries = 3;
        for (int attempt = 0; attempt <= maxRetries; attempt++)
        {
            try
            {
                var json = JsonSerializer.Serialize(transaction, new JsonSerializerOptions
                {
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });

                var message = new Message<string, string>
                {
                    Key = transaction.CustomerId,
                    Value = json,
                    Headers = new Headers
                    {
                        { "correlation-id", System.Text.Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                        { "event-type", System.Text.Encoding.UTF8.GetBytes("transaction.created") },
                        { "source", System.Text.Encoding.UTF8.GetBytes("ebanking-resilient-api") },
                        { "attempt", System.Text.Encoding.UTF8.GetBytes((attempt + 1).ToString()) }
                    },
                    Timestamp = new Timestamp(transaction.Timestamp)
                };

                var result = await _producer.ProduceAsync(_topic, message, ct);

                // Success - reset circuit breaker
                Interlocked.Increment(ref _messagesProduced);
                _consecutiveFailures = 0;

                _logger.LogInformation(
                    "✅ Transaction {Id} sent (attempt {A}) → Partition: {P}, Offset: {O}",
                    transaction.TransactionId, attempt + 1,
                    result.Partition.Value, result.Offset.Value);

                return new TransactionResult
                {
                    TransactionId = transaction.TransactionId,
                    Status = "Processing",
                    KafkaPartition = result.Partition.Value,
                    KafkaOffset = result.Offset.Value,
                    Timestamp = result.Timestamp.UtcDateTime,
                    Attempts = attempt + 1
                };
            }
            catch (ProduceException<string, string> ex)
            {
                _logger.LogWarning("⚠️ Attempt {A}/{Max} failed for {Id}: {Error}",
                    attempt + 1, maxRetries + 1, transaction.TransactionId, ex.Error.Reason);

                TrackError(ex.Error.Code.ToString());

                if (!IsRetriableError(ex.Error.Code) || attempt == maxRetries)
                {
                    // Permanent error or retries exhausted → DLQ
                    Interlocked.Increment(ref _messagesFailed);
                    _consecutiveFailures++;
                    _lastFailure = DateTime.UtcNow;

                    await SendToDlqAsync(transaction, ex.Error.Reason, ex.Error.Code.ToString());

                    return new TransactionResult
                    {
                        TransactionId = transaction.TransactionId,
                        Status = "SentToDLQ",
                        ErrorMessage = $"Error: {ex.Error.Reason} (Code: {ex.Error.Code})",
                        Attempts = attempt + 1
                    };
                }

                // Exponential backoff: 1s, 2s, 4s
                var delayMs = (int)Math.Pow(2, attempt) * 1000;
                _logger.LogInformation("⏳ Retrying in {Delay}ms...", delayMs);
                await Task.Delay(delayMs, ct);
            }
        }

        return new TransactionResult
        {
            TransactionId = transaction.TransactionId,
            Status = "Failed",
            ErrorMessage = "Unexpected: all retries exhausted"
        };
    }

    private async Task SendToDlqAsync(Transaction transaction, string errorMessage, string errorCode)
    {
        try
        {
            var json = JsonSerializer.Serialize(transaction, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });

            var dlqMessage = new Message<string, string>
            {
                Key = transaction.CustomerId,
                Value = json,
                Headers = new Headers
                {
                    { "original-topic", System.Text.Encoding.UTF8.GetBytes(_topic) },
                    { "error-timestamp", System.Text.Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) },
                    { "error-code", System.Text.Encoding.UTF8.GetBytes(errorCode) },
                    { "error-message", System.Text.Encoding.UTF8.GetBytes(errorMessage) },
                    { "transaction-id", System.Text.Encoding.UTF8.GetBytes(transaction.TransactionId) }
                }
            };

            await _dlqProducer.ProduceAsync(_dlqTopic, dlqMessage);
            Interlocked.Increment(ref _messagesSentToDlq);

            _logger.LogWarning("💀 Transaction {Id} sent to DLQ: {Error}",
                transaction.TransactionId, errorMessage);
        }
        catch (Exception dlqEx)
        {
            // DLQ failed → fallback to local file
            _logger.LogError(dlqEx, "❌ DLQ failed for {Id}. Saving to local file.",
                transaction.TransactionId);
            await SaveToLocalFileAsync(transaction, errorMessage, dlqEx.Message);
        }
    }

    private async Task SaveToLocalFileAsync(Transaction transaction, string originalError, string dlqError)
    {
        try 
        {
            var fallbackDir = Path.Combine(AppContext.BaseDirectory, "fallback");
            if (!Directory.Exists(fallbackDir)) Directory.CreateDirectory(fallbackDir);

            var entry = new
            {
                Timestamp = DateTime.UtcNow,
                Transaction = transaction,
                OriginalError = originalError,
                DlqError = dlqError
            };

            var json = JsonSerializer.Serialize(entry, new JsonSerializerOptions { WriteIndented = true });
            var fileName = $"failed-tx-{transaction.TransactionId}-{DateTime.UtcNow:yyyyMMddHHmmss}.json";
            await File.AppendAllTextAsync(Path.Combine(fallbackDir, fileName), json + Environment.NewLine);

            Interlocked.Increment(ref _messagesSavedToFile);
            _logger.LogCritical("💾 Transaction {Id} saved to fallback file: {File}",
                transaction.TransactionId, fileName);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FAILED TO SAVE FALLBACK FILE for {Id}", transaction.TransactionId);
        }
    }

    private bool IsCircuitOpen() =>
        _consecutiveFailures >= CircuitBreakerThreshold &&
        DateTime.UtcNow - _lastFailure < CircuitBreakerTimeout;

    private static bool IsRetriableError(ErrorCode code) => code switch
    {
        ErrorCode.Local_Transport => true,
        ErrorCode.Local_TimedOut => true,
        ErrorCode.NotEnoughReplicas => true,
        ErrorCode.LeaderNotAvailable => true,
        ErrorCode.RequestTimedOut => true,
        _ => false
    };

    private void TrackError(string errorCode)
    {
        lock (_errorCounts)
        {
            _errorCounts[errorCode] = _errorCounts.GetValueOrDefault(errorCode, 0) + 1;
        }
    }

    /// <summary>
    /// Get producer metrics
    /// </summary>
    public ProducerMetrics GetMetrics() => new()
    {
        MessagesProduced = _messagesProduced,
        MessagesFailed = _messagesFailed,
        MessagesSentToDlq = _messagesSentToDlq,
        MessagesSavedToFile = _messagesSavedToFile,
        CircuitBreakerOpen = IsCircuitOpen(),
        ConsecutiveFailures = _consecutiveFailures,
        ErrorCounts = new Dictionary<string, int>(_errorCounts),
        SuccessRate = (_messagesProduced + _messagesFailed) > 0
            ? (double)_messagesProduced / (_messagesProduced + _messagesFailed) * 100
            : 100
    };

    /// <summary>
    /// Simulate a failure for testing circuit breaker and DLQ
    /// </summary>
    public async Task<TransactionResult> SimulateFailureAsync(Transaction transaction, string errorCode)
    {
        _logger.LogWarning("🧪 SIMULATED failure for {Id}: {Error}", transaction.TransactionId, errorCode);

        Interlocked.Increment(ref _messagesFailed);
        _consecutiveFailures++;
        _lastFailure = DateTime.UtcNow;
        TrackError(errorCode);

        await SendToDlqAsync(transaction, $"Simulated error: {errorCode}", errorCode);

        return new TransactionResult
        {
            TransactionId = transaction.TransactionId,
            Status = "SentToDLQ",
            ErrorMessage = $"Simulated error: {errorCode}",
            Attempts = 1
        };
    }

    /// <summary>
    /// Reset circuit breaker state for testing
    /// </summary>
    public void ResetCircuitBreaker()
    {
        _consecutiveFailures = 0;
        _lastFailure = DateTime.MinValue;
        _logger.LogInformation("🔄 Circuit breaker RESET");
    }

    public void Dispose()
    {
        _producer?.Flush(TimeSpan.FromSeconds(10));
        _producer?.Dispose();
        _dlqProducer?.Flush(TimeSpan.FromSeconds(10));
        _dlqProducer?.Dispose();
    }
}

// --- Result and Metrics DTOs ---

public class TransactionResult
{
    public string TransactionId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int KafkaPartition { get; set; }
    public long KafkaOffset { get; set; }
    public DateTime Timestamp { get; set; }
    public int Attempts { get; set; }
    public string? ErrorMessage { get; set; }
}

public class ProducerMetrics
{
    public long MessagesProduced { get; set; }
    public long MessagesFailed { get; set; }
    public long MessagesSentToDlq { get; set; }
    public long MessagesSavedToFile { get; set; }
    public bool CircuitBreakerOpen { get; set; }
    public int ConsecutiveFailures { get; set; }
    public Dictionary<string, int> ErrorCounts { get; set; } = new();
    public double SuccessRate { get; set; }
}
