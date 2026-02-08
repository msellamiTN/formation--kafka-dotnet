using System.Collections.Concurrent;
using System.Text.Json;
using Confluent.Kafka;
using EBankingFraudDetectionAPI.Models;

namespace EBankingFraudDetectionAPI.Services;

public class KafkaConsumerService : BackgroundService
{
    private readonly ILogger<KafkaConsumerService> _logger;
    private readonly IConfiguration _configuration;

    // In-Memory Storage for alerts and metrics
    private readonly ConcurrentBag<FraudAlert> _alerts = new();
    private readonly ConcurrentDictionary<int, long> _partitionOffsets = new();
    private long _messagesConsumed;
    private long _fraudAlerts;
    private long _processingErrors;
    private double _totalRiskScore;
    private DateTime _startedAt;
    private DateTime _lastMessageAt;
    private string _status = "Starting";

    public KafkaConsumerService(
        ILogger<KafkaConsumerService> logger,
        IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _startedAt = DateTime.UtcNow;
        _status = "Running";

        var config = new ConsumerConfig
        {
            BootstrapServers = _configuration["Kafka:BootstrapServers"] ?? "localhost:9092",
            GroupId = _configuration["Kafka:GroupId"] ?? "fraud-detection-service",
            ClientId = $"fraud-detector-{Environment.MachineName}-{Guid.NewGuid():N}",
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = true,
            AutoCommitIntervalMs = 5000,
            SessionTimeoutMs = 10000,
            HeartbeatIntervalMs = 3000,
            MaxPollIntervalMs = 300000,
            PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
        };

        var topic = _configuration["Kafka:Topic"] ?? "banking.transactions";

        _logger.LogInformation(
            "Starting Fraud Detection Consumer. Group: {Group}, Topic: {Topic}, Servers: {Servers}",
            config.GroupId, topic, config.BootstrapServers);

        using var consumer = new ConsumerBuilder<string, string>(config)
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Consumer error: Code={Code}, Reason={Reason}, IsFatal={IsFatal}",
                    e.Code, e.Reason, e.IsFatal);
                if (e.IsFatal) _status = "Fatal Error";
            })
            .SetPartitionsAssignedHandler((c, partitions) =>
            {
                _logger.LogInformation("✅ Partitions assigned: {Partitions}",
                    string.Join(", ", partitions.Select(p => $"[{p.Partition.Value}]")));
                _status = "Consuming";
            })
            .SetPartitionsRevokedHandler((c, partitions) =>
            {
                _logger.LogWarning("⚠️ Partitions revoked: {Partitions}",
                    string.Join(", ", partitions.Select(p => $"[{p.Partition.Value}]")));
                _status = "Rebalancing";
            })
            .SetPartitionsLostHandler((c, partitions) =>
            {
                _logger.LogError("❌ Partitions lost: {Partitions}",
                    string.Join(", ", partitions.Select(p => $"[{p.Partition.Value}]")));
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

                    await ProcessMessageAsync(consumeResult);
                }
                catch (ConsumeException ex)
                {
                    _logger.LogError(ex, "Consume error: {Reason}", ex.Error.Reason);
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
            _logger.LogCritical(ex, "Uncaught exception in Consumer loop");
            _status = "Faulted";
        }
        finally
        {
            _status = "Stopped";
            consumer.Close();
            _logger.LogInformation("Consumer closed gracefully");
        }
    }

    private async Task ProcessMessageAsync(ConsumeResult<string, string> result)
    {
        try
        {
            // Deserialize the transaction
            var transaction = JsonSerializer.Deserialize<Transaction>(result.Message.Value);
            if (transaction == null)
            {
                _logger.LogWarning("Failed to deserialize message at P{Partition}:O{Offset}",
                    result.Partition.Value, result.Offset.Value);
                Interlocked.Increment(ref _processingErrors);
                return;
            }

            // Calculate risk score
            var (riskScore, riskLevel, reason) = CalculateRiskScore(transaction);

            // Update metrics
            Interlocked.Increment(ref _messagesConsumed);
            _totalRiskScore += riskScore;
            _lastMessageAt = DateTime.UtcNow;
            _partitionOffsets[result.Partition.Value] = result.Offset.Value;

            _logger.LogInformation(
                "📦 Transaction {TxId} | Customer: {Customer} | {Amount} {Currency} | Risk: {Score}/100 ({Level}) | P{Partition}:O{Offset}",
                transaction.TransactionId, transaction.CustomerId,
                transaction.Amount, transaction.Currency,
                riskScore, riskLevel,
                result.Partition.Value, result.Offset.Value);

            // Create alert if high risk
            if (riskScore >= 40)
            {
                var alert = new FraudAlert
                {
                    TransactionId = transaction.TransactionId,
                    CustomerId = transaction.CustomerId,
                    Amount = transaction.Amount,
                    Currency = transaction.Currency,
                    Type = transaction.Type.ToString(), // Ensure string representation
                    RiskScore = riskScore,
                    RiskLevel = riskLevel,
                    Reason = reason,
                    KafkaPartition = result.Partition.Value,
                    KafkaOffset = result.Offset.Value
                };

                _alerts.Add(alert);
                Interlocked.Increment(ref _fraudAlerts);

                _logger.LogWarning(
                    "🚨 FRAUD ALERT: {TxId} | {Customer} | {Amount}{Currency} | Score: {Score} | {Reason}",
                    transaction.TransactionId, transaction.CustomerId,
                    transaction.Amount, transaction.Currency,
                    riskScore, reason);
            }

            // Simulate processing time
            await Task.Delay(50);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing message at P{Partition}:O{Offset}",
                result.Partition.Value, result.Offset.Value);
            Interlocked.Increment(ref _processingErrors);
        }
    }

    private (int score, string level, string reason) CalculateRiskScore(Transaction tx)
    {
        int score = 0;
        var reasons = new List<string>();

        // Rule 1: High Amount
        if (tx.Amount > 10000)
        {
            score += 40;
            reasons.Add($"High amount: {tx.Amount}{tx.Currency}");
        }
        else if (tx.Amount > 5000)
        {
            score += 20;
            reasons.Add($"Large amount: {tx.Amount}{tx.Currency}");
        }

        // Rule 2: Transaction Type Risk (Simulated)
        if (tx.Type == 2) // Assuming 2 is Withdrawal/International in our logic
        {
            score += 30;
            reasons.Add("High-risk transaction type");
        }

        // Rule 3: Late night transactions
        if (tx.Timestamp.Hour < 6 || tx.Timestamp.Hour > 22)
        {
            score += 15;
            reasons.Add("Off-hours transaction");
        }

        // Rule 4: Producer-reported risk
        if (tx.RiskScore > 50)
        {
            score += 20;
            reasons.Add($"Original risk score high: {tx.RiskScore}");
        }

        score = Math.Min(score, 100);

        var level = score switch
        {
            >= 75 => "Critical",
            >= 50 => "High",
            >= 25 => "Medium",
            _ => "Low"
        };

        return (score, level, string.Join(" | ", reasons.DefaultIfEmpty("No significant risk factors")));
    }

    // Public methods for API access
    public IReadOnlyList<FraudAlert> GetAlerts() => _alerts.ToList().AsReadOnly();

    public IReadOnlyList<FraudAlert> GetHighRiskAlerts() =>
        _alerts.Where(a => a.RiskScore >= 50).OrderByDescending(a => a.RiskScore).ToList().AsReadOnly();

    public ConsumerMetrics GetMetrics() => new()
    {
        MessagesConsumed = Interlocked.Read(ref _messagesConsumed),
        FraudAlertsGenerated = Interlocked.Read(ref _fraudAlerts),
        ProcessingErrors = Interlocked.Read(ref _processingErrors),
        AverageRiskScore = _messagesConsumed > 0 ? _totalRiskScore / _messagesConsumed : 0,
        ConsumerGroupId = _configuration["Kafka:GroupId"] ?? "fraud-detection-service",
        ConsumerStatus = _status,
        PartitionOffsets = new Dictionary<int, long>(_partitionOffsets),
        StartedAt = _startedAt,
        LastMessageAt = _lastMessageAt
    };
}
