using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using Confluent.Kafka;
using EBankingTransactionsAPI.Models;

namespace EBankingTransactionsAPI.Services;

/// <summary>
/// Kafka Producer with Exactly-Once Semantics using Transactions
/// </summary>
public class TransactionalProducerService : IDisposable
{
    private readonly IProducer<string, string> _producer;
    private readonly ILogger<TransactionalProducerService> _logger;
    private readonly string _topic;
    private readonly string _transactionalId;
    private readonly JsonSerializerOptions _jsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    // Metrics
    private long _transactionsProduced;
    private long _transactionsCommitted;
    private long _transactionsAborted;
    private long _activeTransactions;
    private DateTime _lastTransactionAt;
    private readonly ConcurrentBag<TransactionResult> _recentTransactions = new();

    public TransactionalProducerService(IConfiguration config, ILogger<TransactionalProducerService> logger)
    {
        _logger = logger;
        _topic = config["Kafka:Topic"] ?? "banking.transactions";
        _transactionalId = config["Kafka:TransactionalId"] ?? "ebanking-payment-producer";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = config["Kafka:BootstrapServers"] ?? "localhost:9092",
            ClientId = "ebanking-transactional-producer",

            // ═══ TRANSACTIONAL CONFIGURATION ═══
            // This is the KEY for exactly-once semantics
            TransactionalId = _transactionalId,
            
            // These are FORCED by TransactionalId:
            EnableIdempotence = true,           // Required for transactions
            Acks = Acks.All,                     // Required for transactions
            MaxInFlight = 5,                     // Required for transactions
            
            // Performance tuning
            LingerMs = 10,
            BatchSize = 16384,
            CompressionType = CompressionType.Snappy,
            RetryBackoffMs = 100,
            
            // Transaction timeout (important!)
            TransactionTimeoutMs = 60000,        // 60 seconds
            TransactionalTimeoutMs = 60000      // 60 seconds
        };

        _producer = new ProducerBuilder<string, string>(producerConfig)
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Transactional producer error: {Code} - {Reason} (Fatal={Fatal})",
                    e.Code, e.Reason, e.IsFatal);
            })
            .SetLogHandler((_, log) =>
            {
                if (log.Message.Contains("transaction") || log.Message.Contains("Transaction"))
                {
                    _logger.LogInformation("TRANSACTION: {Message}", log.Message);
                }
            })
            .Build();

        // Initialize transactions
        try
        {
            _producer.InitTransactions(TimeSpan.FromSeconds(30));
            _logger.LogInformation("✅ Transactions initialized. TransactionalId: {TransactionalId}", _transactionalId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize transactions");
            throw;
        }
    }

    /// <summary>
    /// Send multiple transactions in a single atomic transaction
    /// </summary>
    public async Task<List<TransactionResult>> SendTransactionBatchAsync(
        List<Transaction> transactions, CancellationToken ct = default)
    {
        var results = new List<TransactionResult>();
        
        try
        {
            Interlocked.Increment(ref _activeTransactions);
            _lastTransactionAt = DateTime.UtcNow;

            // Begin transaction
            _producer.BeginTransaction();
            _logger.LogInformation("🔒 Transaction begun for {Count} transactions", transactions.Count);

            // Send all messages within the transaction
            foreach (var tx in transactions)
            {
                var json = JsonSerializer.Serialize(tx, _jsonOptions);
                
                var message = new Message<string, string>
                {
                    Key = tx.CustomerId,
                    Value = json,
                    Headers = new Headers
                    {
                        { "transaction-type", Encoding.UTF8.GetBytes("atomic-batch") },
                        { "batch-id", Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                        { "source", Encoding.UTF8.GetBytes("ebanking-transactional-api") },
                        { "transactional-id", Encoding.UTF8.GetBytes(_transactionalId) }
                    },
                    Timestamp = new Timestamp(tx.Timestamp)
                };

                var result = await _producer.ProduceAsync(_topic, message, ct);
                
                var txResult = new TransactionResult
                {
                    TransactionId = tx.TransactionId,
                    Status = "Produced",
                    TransactionalId = _transactionalId,
                    Partition = result.Partition.Value,
                    Offset = result.Offset.Value,
                    Timestamp = result.Timestamp.UtcDateTime
                };
                
                results.Add(txResult);
                Interlocked.Increment(ref _transactionsProduced);
                
                _logger.LogInformation("📤 Produced in transaction: {TxId} → P{Partition}:O{Offset}",
                    tx.TransactionId, result.Partition.Value, result.Offset.Value);
            }

            // Send offsets to transaction (optional - for consume-process-produce pattern)
            // _producer.SendOffsetsToTransaction(GetConsumerOffsets(), _consumer.ConsumerGroupMetadata);

            // Commit transaction
            _producer.CommitTransaction();
            Interlocked.Increment(ref _transactionsCommitted);
            Interlocked.Decrement(ref _activeTransactions);
            
            _logger.LogInformation("✅ Transaction committed: {Count} transactions", transactions.Count);

            // Store results for metrics
            foreach (var result in results)
            {
                _recentTransactions.Add(result);
            }

            return results;
        }
        catch (Exception ex)
        {
            // Abort transaction on error
            try
            {
                _producer.AbortTransaction();
                Interlocked.Increment(ref _transactionsAborted);
                Interlocked.Decrement(ref _activeTransactions);
                _logger.LogError(ex, "❌ Transaction aborted: {Error}", ex.Message);
            }
            catch (Exception abortEx)
            {
                _logger.LogError(abortEx, "Failed to abort transaction");
            }

            // Return error results
            return transactions.Select(tx => new TransactionResult
            {
                TransactionId = tx.TransactionId,
                Status = "Failed",
                TransactionalId = _transactionalId,
                ErrorMessage = ex.Message
            }).ToList();
        }
    }

    /// <summary>
    /// Send a single transaction atomically
    /// </summary>
    public async Task<TransactionResult> SendTransactionAsync(
        Transaction transaction, CancellationToken ct = default)
    {
        var batchResult = await SendTransactionBatchAsync(new List<Transaction> { transaction }, ct);
        return batchResult.FirstOrDefault() ?? new TransactionResult
        {
            TransactionId = transaction.TransactionId,
            Status = "Failed",
            TransactionalId = _transactionalId,
            ErrorMessage = "No result returned"
        };
    }

    public TransactionalMetrics GetMetrics() => new()
    {
        TransactionalId = _transactionalId,
        TransactionsProduced = Interlocked.Read(ref _transactionsProduced),
        TransactionsCommitted = Interlocked.Read(ref _transactionsCommitted),
        TransactionsAborted = Interlocked.Read(ref _transactionsAborted),
        ActiveTransactions = Interlocked.Read(ref _activeTransactions),
        ProducerState = _activeTransactions > 0 ? "In Transaction" : "Ready",
        LastTransactionAt = _lastTransactionAt
    };

    public void Dispose()
    {
        try
        {
            // Ensure no active transactions before disposing
            if (Interlocked.Read(ref _activeTransactions) > 0)
            {
                _logger.LogWarning("Disposing producer with {Count} active transactions", 
                    Interlocked.Read(ref _activeTransactions));
            }
            
            _producer?.Flush(TimeSpan.FromSeconds(10));
            _producer?.Dispose();
            _logger.LogInformation("Transactional producer disposed");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error disposing transactional producer");
        }
    }
}
