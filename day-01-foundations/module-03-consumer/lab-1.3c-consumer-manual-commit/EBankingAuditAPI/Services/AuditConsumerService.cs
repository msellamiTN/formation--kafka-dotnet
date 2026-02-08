using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using Confluent.Kafka;
using EBankingAuditAPI.Models;

namespace EBankingAuditAPI.Services;

public class AuditConsumerService : BackgroundService
{
    private readonly ILogger<AuditConsumerService> _logger;
    private readonly IConfiguration _configuration;

    // Audit store (in-memory, idempotent par TransactionId)
    private readonly ConcurrentDictionary<string, AuditRecord> _auditLog = new();
    private readonly ConcurrentBag<DlqMessage> _dlqMessages = new();
    private readonly ConcurrentDictionary<int, long> _committedOffsets = new();

    // Métriques
    private long _messagesConsumed;
    private long _auditRecords;
    private long _duplicatesSkipped;
    private long _processingErrors;
    private long _dlqCount;
    private long _manualCommits;
    private DateTime _startedAt;
    private DateTime _lastCommitAt;
    private DateTime _lastMessageAt;
    private string _status = "Starting";

    // DLQ Producer
    private IProducer<string, string>? _dlqProducer;

    // Commit batching
    private const int CommitBatchSize = 10;
    private int _uncommittedCount;

    public AuditConsumerService(
        ILogger<AuditConsumerService> logger,
        IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _startedAt = DateTime.UtcNow;
        _status = "Running";

        var bootstrapServers = _configuration["Kafka:BootstrapServers"] ?? "localhost:9092";

        var config = new ConsumerConfig
        {
            BootstrapServers = bootstrapServers,
            GroupId = _configuration["Kafka:GroupId"] ?? "audit-compliance-service",
            ClientId = $"audit-worker-{Environment.MachineName}-{Guid.NewGuid().ToString()[..8]}",
            AutoOffsetReset = AutoOffsetReset.Earliest,

            // *** MANUAL COMMIT : clé de ce lab ***
            EnableAutoCommit = false,

            SessionTimeoutMs = 10000,
            HeartbeatIntervalMs = 3000,
            MaxPollIntervalMs = 300000,
            PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
        };

        var topic = _configuration["Kafka:Topic"] ?? "banking.transactions";
        var dlqTopic = _configuration["Kafka:DlqTopic"] ?? "banking.transactions.audit-dlq";

        // Créer le DLQ producer
        _dlqProducer = new ProducerBuilder<string, string>(new ProducerConfig
        {
            BootstrapServers = bootstrapServers,
            ClientId = "audit-dlq-producer",
            Acks = Acks.All
        }).Build();

        _logger.LogInformation(
            "🚀 Starting Audit Consumer. Group: {Group}, Topic: {Topic}, ManualCommit: ENABLED",
            config.GroupId, topic);

        using var consumer = new ConsumerBuilder<string, string>(config)
            .SetErrorHandler((_, e) =>
            {
                _logger.LogError("Consumer error: {Code} - {Reason}", e.Code, e.Reason);
                if (e.IsFatal) _status = "Fatal Error";
            })
            .SetPartitionsAssignedHandler((c, partitions) =>
            {
                _logger.LogInformation("✅ Partitions assigned: [{Partitions}]",
                    string.Join(", ", partitions.Select(p => p.Partition.Value)));
                _status = "Consuming";
            })
            .SetPartitionsRevokedHandler((c, partitions) =>
            {
                // IMPORTANT : Commit avant que les partitions soient révoquées
                _logger.LogWarning("⚠️ Partitions revoked: [{Partitions}] — Committing offsets before revocation",
                    string.Join(", ", partitions.Select(p => p.Partition.Value)));
                try
                {
                    c.Commit();
                    Interlocked.Increment(ref _manualCommits);
                    _lastCommitAt = DateTime.UtcNow;
                    _logger.LogInformation("✅ Offsets committed before revocation");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to commit offsets during revocation");
                }
                _status = "Rebalancing";
            })
            .SetPartitionsLostHandler((c, partitions) =>
            {
                _logger.LogError("❌ Partitions lost: [{Partitions}] — Offsets may not be committed",
                    string.Join(", ", partitions.Select(p => p.Partition.Value)));
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
                    var consumeResult = consumer.Consume(stoppingToken);
                    if (consumeResult == null) continue;

                    var success = await ProcessWithRetryAsync(consumeResult, dlqTopic);

                    // Stocker l'offset pour commit (que le traitement ait réussi ou envoyé en DLQ)
                    consumer.StoreOffset(consumeResult);
                    _uncommittedCount++;

                    // Commit par batch ou par intervalle
                    if (_uncommittedCount >= CommitBatchSize)
                    {
                        consumer.Commit();
                        Interlocked.Increment(ref _manualCommits);
                        _lastCommitAt = DateTime.UtcNow;
                        _committedOffsets[consumeResult.Partition.Value] = consumeResult.Offset.Value;
                        _uncommittedCount = 0;

                        _logger.LogDebug("💾 Manual commit: P{Partition}:O{Offset} ({Batch} messages)",
                            consumeResult.Partition.Value, consumeResult.Offset.Value, CommitBatchSize);
                    }
                }
                catch (ConsumeException ex)
                {
                    _logger.LogError(ex, "Consume error: {Reason}", ex.Error.Reason);
                    Interlocked.Increment(ref _processingErrors);
                }
            }
        }
        catch (OperationCanceledException)
        {
            _logger.LogInformation("Consumer shutdown requested");
        }
        finally
        {
            // GRACEFUL SHUTDOWN : commit final avant fermeture
            _logger.LogInformation("🛑 Graceful shutdown: committing final offsets...");
            try
            {
                consumer.Commit();
                Interlocked.Increment(ref _manualCommits);
                _lastCommitAt = DateTime.UtcNow;
                _logger.LogInformation("✅ Final offsets committed successfully");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to commit final offsets");
            }

            _status = "Stopped";
            consumer.Close();
            _dlqProducer?.Dispose();
            _logger.LogInformation("Consumer closed gracefully. Total commits: {Commits}", _manualCommits);
        }
    }

    private async Task<bool> ProcessWithRetryAsync(
        ConsumeResult<string, string> result,
        string dlqTopic,
        int maxRetries = 3)
    {
        Interlocked.Increment(ref _messagesConsumed);
        _lastMessageAt = DateTime.UtcNow;

        for (int attempt = 1; attempt <= maxRetries; attempt++)
        {
            try
            {
                var transaction = JsonSerializer.Deserialize<Transaction>(result.Message.Value);
                if (transaction == null)
                {
                    _logger.LogWarning("Failed to deserialize message at P{Partition}:O{Offset}",
                        result.Partition.Value, result.Offset.Value);
                    await SendToDlqAsync(result, dlqTopic, "Deserialization failed", attempt);
                    return false;
                }

                // IDEMPOTENCE : vérifier si déjà traité
                if (_auditLog.ContainsKey(transaction.TransactionId))
                {
                    Interlocked.Increment(ref _duplicatesSkipped);
                    _logger.LogInformation(
                        "⏭️ Duplicate skipped: {TxId} (already in audit log) | P{Partition}:O{Offset}",
                        transaction.TransactionId, result.Partition.Value, result.Offset.Value);
                    return true;
                }

                // Créer l'enregistrement d'audit
                var auditRecord = new AuditRecord
                {
                    TransactionId = transaction.TransactionId,
                    CustomerId = transaction.CustomerId,
                    Amount = transaction.Amount,
                    Currency = transaction.Currency,
                    Type = transaction.Type,
                    FromAccount = transaction.FromAccount,
                    ToAccount = transaction.ToAccount,
                    TransactionTimestamp = transaction.Timestamp,
                    KafkaPartition = result.Partition.Value,
                    KafkaOffset = result.Offset.Value,
                    ConsumerGroupId = _configuration["Kafka:GroupId"] ?? "audit-compliance-service",
                    ProcessingAttempts = attempt
                };

                // Persister (in-memory, simule une écriture en base)
                _auditLog[transaction.TransactionId] = auditRecord;
                Interlocked.Increment(ref _auditRecords);

                _logger.LogInformation(
                    "📋 Audit recorded: {TxId} | {Customer} | {Amount}{Currency} | {Type} | P{Partition}:O{Offset} | Attempt {Attempt}",
                    transaction.TransactionId, transaction.CustomerId,
                    transaction.Amount, transaction.Currency, transaction.Type,
                    result.Partition.Value, result.Offset.Value, attempt);

                // Simuler persistance en base (peut échouer)
                await Task.Delay(30);
                return true;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex,
                    "Processing attempt {Attempt}/{Max} failed for P{Partition}:O{Offset}",
                    attempt, maxRetries, result.Partition.Value, result.Offset.Value);

                if (attempt < maxRetries)
                {
                    var delay = TimeSpan.FromSeconds(Math.Pow(2, attempt - 1));
                    _logger.LogInformation("⏳ Retrying in {Delay}s...", delay.TotalSeconds);
                    await Task.Delay(delay);
                }
                else
                {
                    Interlocked.Increment(ref _processingErrors);
                    await SendToDlqAsync(result, dlqTopic, ex.Message, attempt);
                    return false;
                }
            }
        }
        return false;
    }

    private async Task SendToDlqAsync(
        ConsumeResult<string, string> failedMessage,
        string dlqTopic,
        string errorReason,
        int attempts)
    {
        if (_dlqProducer == null) return;

        try
        {
            var dlqMessage = new Message<string, string>
            {
                Key = failedMessage.Message.Key,
                Value = failedMessage.Message.Value,
                Headers = new Headers
                {
                    { "original-topic", Encoding.UTF8.GetBytes("banking.transactions") },
                    { "original-partition", Encoding.UTF8.GetBytes(failedMessage.Partition.Value.ToString()) },
                    { "original-offset", Encoding.UTF8.GetBytes(failedMessage.Offset.Value.ToString()) },
                    { "error-reason", Encoding.UTF8.GetBytes(errorReason) },
                    { "attempts", Encoding.UTF8.GetBytes(attempts.ToString()) },
                    { "consumer-group", Encoding.UTF8.GetBytes(_configuration["Kafka:GroupId"] ?? "") },
                    { "failed-at", Encoding.UTF8.GetBytes(DateTime.UtcNow.ToString("o")) }
                }
            };

            await _dlqProducer.ProduceAsync(dlqTopic, dlqMessage);
            Interlocked.Increment(ref _dlqCount);

            _dlqMessages.Add(new DlqMessage
            {
                TransactionId = failedMessage.Message.Key ?? "unknown",
                OriginalMessage = failedMessage.Message.Value,
                ErrorReason = errorReason,
                Attempts = attempts,
                OriginalPartition = failedMessage.Partition.Value,
                OriginalOffset = failedMessage.Offset.Value
            });

            _logger.LogWarning(
                "☠️ Sent to DLQ: Key={Key} | P{Partition}:O{Offset} | Reason: {Reason}",
                failedMessage.Message.Key, failedMessage.Partition.Value,
                failedMessage.Offset.Value, errorReason);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send message to DLQ");
        }
    }

    // Méthodes publiques pour l'API
    public IReadOnlyList<AuditRecord> GetAuditLog() =>
        _auditLog.Values.OrderByDescending(a => a.AuditTimestamp).ToList().AsReadOnly();

    public AuditRecord? GetAuditRecord(string transactionId) =>
        _auditLog.GetValueOrDefault(transactionId);

    public IReadOnlyList<DlqMessage> GetDlqMessages() =>
        _dlqMessages.ToList().AsReadOnly();

    public AuditMetrics GetMetrics() => new()
    {
        MessagesConsumed = Interlocked.Read(ref _messagesConsumed),
        AuditRecordsCreated = Interlocked.Read(ref _auditRecords),
        DuplicatesSkipped = Interlocked.Read(ref _duplicatesSkipped),
        ProcessingErrors = Interlocked.Read(ref _processingErrors),
        MessagesSentToDlq = Interlocked.Read(ref _dlqCount),
        ManualCommits = Interlocked.Read(ref _manualCommits),
        ConsumerStatus = _status,
        GroupId = _configuration["Kafka:GroupId"] ?? "audit-compliance-service",
        CommittedOffsets = new Dictionary<int, long>(_committedOffsets),
        StartedAt = _startedAt,
        LastCommitAt = _lastCommitAt,
        LastMessageAt = _lastMessageAt
    };
}
