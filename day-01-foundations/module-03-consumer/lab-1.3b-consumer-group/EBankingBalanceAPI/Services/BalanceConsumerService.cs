using System.Collections.Concurrent;
using System.Text.Json;
using Confluent.Kafka;
using EBankingBalanceAPI.Models;

namespace EBankingBalanceAPI.Services;

public class BalanceConsumerService : BackgroundService
{
    private readonly ILogger<BalanceConsumerService> _logger;
    private readonly IConfiguration _configuration;

    // In-Memory Storage for balances (thread-safe)
    private readonly ConcurrentDictionary<string, CustomerBalance> _balances = new();
    private readonly ConcurrentDictionary<int, long> _partitionOffsets = new();
    private readonly ConcurrentBag<RebalancingEvent> _rebalancingHistory = new();
    private readonly List<int> _assignedPartitions = new();
    private readonly object _partitionLock = new();

    private long _messagesConsumed;
    private long _balanceUpdates;
    private long _processingErrors;
    private DateTime _startedAt;
    private DateTime _lastMessageAt;
    private string _status = "Starting";
    private string _consumerId = string.Empty;

    public BalanceConsumerService(
        ILogger<BalanceConsumerService> logger,
        IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _startedAt = DateTime.UtcNow;
        _consumerId = $"balance-worker-{Environment.MachineName}-{Guid.NewGuid().ToString()[..8]}";
        _status = "Running";

        var config = new ConsumerConfig
        {
            BootstrapServers = _configuration["Kafka:BootstrapServers"] ?? "localhost:9092",
            GroupId = _configuration["Kafka:GroupId"] ?? "balance-service",
            ClientId = _consumerId,
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = true,
            AutoCommitIntervalMs = 5000,
            SessionTimeoutMs = 10000,
            HeartbeatIntervalMs = 3000,
            MaxPollIntervalMs = 300000,
            // CooperativeSticky: incremental rebalancing (no stop-the-world)
            PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
        };

        var topic = _configuration["Kafka:Topic"] ?? "banking.transactions";

        _logger.LogInformation(
            "🚀 Starting Balance Consumer [{ConsumerId}]. Group: {Group}, Topic: {Topic}",
            _consumerId, config.GroupId, topic);

        using var consumer = new ConsumerBuilder<string, string>(config)
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("[{Consumer}] Error: {Code} - {Reason}", _consumerId, e.Code, e.Reason);
                if (e.IsFatal) _status = "Fatal Error";
            })
            .SetPartitionsAssignedHandler((c, partitions) =>
            {
                var partitionIds = partitions.Select(p => p.Partition.Value).ToList();
                lock (_partitionLock)
                {
                    _assignedPartitions.Clear();
                    _assignedPartitions.AddRange(partitionIds);
                }

                _rebalancingHistory.Add(new RebalancingEvent
                {
                    EventType = "Assigned",
                    Partitions = partitionIds,
                    Details = $"Consumer {_consumerId} received {partitionIds.Count} partitions"
                });

                _logger.LogInformation(
                    "✅ [{Consumer}] Partitions ASSIGNED: [{Partitions}]",
                    _consumerId, string.Join(", ", partitionIds));
                _status = "Consuming";
            })
            .SetPartitionsRevokedHandler((c, partitions) =>
            {
                var partitionIds = partitions.Select(p => p.Partition.Value).ToList();

                _rebalancingHistory.Add(new RebalancingEvent
                {
                    EventType = "Revoked",
                    Partitions = partitionIds,
                    Details = $"Consumer {_consumerId} lost {partitionIds.Count} partitions (rebalancing)"
                });

                _logger.LogWarning(
                    "⚠️ [{Consumer}] Partitions REVOKED: [{Partitions}] — Rebalancing in progress",
                    _consumerId, string.Join(", ", partitionIds));
                _status = "Rebalancing";
            })
            .SetPartitionsLostHandler((c, partitions) =>
            {
                var partitionIds = partitions.Select(p => p.Partition.Value).ToList();

                _rebalancingHistory.Add(new RebalancingEvent
                {
                    EventType = "Lost",
                    Partitions = partitionIds,
                    Details = $"Consumer {_consumerId} unexpectedly lost {partitionIds.Count} partitions"
                });

                _logger.LogError(
                    "❌ [{Consumer}] Partitions LOST: [{Partitions}]",
                    _consumerId, string.Join(", ", partitionIds));
                _status = "Partitions Lost";
            })
            .Build();

        consumer.Subscribe(topic);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    // Poll for messages
                    var consumeResult = consumer.Consume(stoppingToken);
                    if (consumeResult == null) continue;

                    await ProcessTransactionAsync(consumeResult);
                }
                catch (ConsumeException ex)
                {
                    _logger.LogError(ex, "[{Consumer}] Consume error: {Reason}", _consumerId, ex.Error.Reason);
                    Interlocked.Increment(ref _processingErrors);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogCritical(ex, "[{Consumer}] Uncaught exception in Consumer loop", _consumerId);
            _status = "Faulted";
        }
        finally
        {
            _status = "Stopped";
            consumer.Close();
            _logger.LogInformation("[{Consumer}] Consumer closed gracefully", _consumerId);
        }
    }

    private async Task ProcessTransactionAsync(ConsumeResult<string, string> result)
    {
        try
        {
            var transaction = JsonSerializer.Deserialize<Transaction>(result.Message.Value);
            if (transaction == null)
            {
                Interlocked.Increment(ref _processingErrors);
                return;
            }

            // Update customer balance
            _balances.AddOrUpdate(
                transaction.CustomerId,
                // New customer
                new CustomerBalance
                {
                    CustomerId = transaction.CustomerId,
                    Balance = GetBalanceChange(transaction),
                    TransactionCount = 1,
                    LastUpdated = DateTime.UtcNow,
                    LastTransactionId = transaction.TransactionId
                },
                // Existing customer
                (key, existing) =>
                {
                    existing.Balance += GetBalanceChange(transaction);
                    existing.TransactionCount++;
                    existing.LastUpdated = DateTime.UtcNow;
                    existing.LastTransactionId = transaction.TransactionId;
                    return existing;
                });

            // Update metrics
            Interlocked.Increment(ref _messagesConsumed);
            Interlocked.Increment(ref _balanceUpdates);
            _lastMessageAt = DateTime.UtcNow;
            _partitionOffsets[result.Partition.Value] = result.Offset.Value;

            _logger.LogInformation(
                "💰 [{Consumer}] {Customer}: {Sign}{Amount}{Currency} (type={Type}) → Balance: {Balance}{Currency2} | P{Partition}:O{Offset}",
                _consumerId,
                transaction.CustomerId,
                GetBalanceChange(transaction) >= 0 ? "+" : "",
                Math.Abs(GetBalanceChange(transaction)),
                transaction.Currency,
                transaction.Type,
                _balances[transaction.CustomerId].Balance,
                transaction.Currency,
                result.Partition.Value,
                result.Offset.Value);

            // Simulate processing time
            await Task.Delay(20);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[{Consumer}] Error processing P{Partition}:O{Offset}",
                _consumerId, result.Partition.Value, result.Offset.Value);
            Interlocked.Increment(ref _processingErrors);
        }
    }

    private static decimal GetBalanceChange(Transaction tx)
    {
        // 3=Deposit, 1=Transfer -> credit; 4=Withdrawal, 5=CardPayment, 7=BillPayment -> debit
        return tx.Type switch
        {
            3 or 1 when tx.Amount > 0 => tx.Amount,
            4 or 5 or 7 => -tx.Amount,
            _ => tx.Amount
        };
    }

    // Public methods for API access
    public IReadOnlyDictionary<string, CustomerBalance> GetAllBalances() =>
        new Dictionary<string, CustomerBalance>(_balances);

    public CustomerBalance? GetBalance(string customerId) =>
        _balances.GetValueOrDefault(customerId);

    public ConsumerGroupMetrics GetMetrics()
    {
        List<int> partitions;
        lock (_partitionLock)
        {
            partitions = new List<int>(_assignedPartitions);
        }

        return new ConsumerGroupMetrics
        {
            ConsumerId = _consumerId,
            GroupId = _configuration["Kafka:GroupId"] ?? "balance-service",
            Status = _status,
            AssignedPartitions = partitions,
            MessagesConsumed = Interlocked.Read(ref _messagesConsumed),
            BalanceUpdates = Interlocked.Read(ref _balanceUpdates),
            ProcessingErrors = Interlocked.Read(ref _processingErrors),
            PartitionOffsets = new Dictionary<int, long>(_partitionOffsets),
            RebalancingHistory = _rebalancingHistory.ToList(),
            StartedAt = _startedAt,
            LastMessageAt = _lastMessageAt
        };
    }
}
