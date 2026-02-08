using Confluent.Kafka;
using System.Text.Json;
using EBankingKeyedProducerAPI.Models;

namespace EBankingKeyedProducerAPI.Services;

public class KeyedKafkaProducerService : IDisposable
{
    private readonly IProducer<string, string> _producer;
    private readonly ILogger<KeyedKafkaProducerService> _logger;
    private readonly string _topic;

    // Local statistics for distribution visibility
    private readonly Dictionary<int, int> _partitionStats = new();
    private readonly Dictionary<string, int> _customerPartitionMap = new();

    public KeyedKafkaProducerService(IConfiguration config, ILogger<KeyedKafkaProducerService> logger)
    {
        _logger = logger;
        _topic = config["Kafka:Topic"] ?? "banking.transactions";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = config["Kafka:BootstrapServers"] ?? "localhost:9092",
            ClientId = config["Kafka:ClientId"] ?? "ebanking-keyed-producer-api",
            Acks = Acks.All,
            EnableIdempotence = true,
            MessageSendMaxRetries = 3,
            RetryBackoffMs = 1000,
            LingerMs = 10,
            BatchSize = 16384,
            CompressionType = CompressionType.Snappy
        };

        _producer = new ProducerBuilder<string, string>(producerConfig)
            .SetErrorHandler((_, error) =>
                _logger.LogError("Kafka Error: {Reason} (Code: {Code})", error.Reason, error.Code))
            .SetLogHandler((_, msg) =>
            {
                if (msg.Level >= SyslogLevel.Warning)
                    _logger.LogWarning("Kafka Log: {Message}", msg.Message);
            })
            .Build();

        _logger.LogInformation("Keyed Kafka Producer initialized → {Servers}, Topic: {Topic}", 
            producerConfig.BootstrapServers, _topic);
    }

    /// <summary>
    /// Send transaction with CustomerId as partition key
    /// </summary>
    public async Task<DeliveryResult<string, string>> SendTransactionAsync(
        Transaction transaction, CancellationToken ct = default)
    {
        var json = JsonSerializer.Serialize(transaction, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        // The Key (CustomerId) determines the partition
        var message = new Message<string, string>
        {
            Key = transaction.CustomerId,
            Value = json,
            Headers = new Headers
            {
                { "correlation-id", System.Text.Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                { "event-type", System.Text.Encoding.UTF8.GetBytes("transaction.created") },
                { "partition-key", System.Text.Encoding.UTF8.GetBytes(transaction.CustomerId) }
            },
            Timestamp = new Timestamp(transaction.Timestamp)
        };

        var result = await _producer.ProduceAsync(_topic, message, ct);

        // Update local stats
        var partition = result.Partition.Value;
        lock (_partitionStats)
        {
            _partitionStats[partition] = _partitionStats.GetValueOrDefault(partition, 0) + 1;
            _customerPartitionMap[transaction.CustomerId] = partition;
        }

        _logger.LogInformation("✅ Produced → Key: {Key}, Partition: {Partition}, Offset: {Offset}",
            transaction.CustomerId, partition, result.Offset.Value);

        return result;
    }

    public Dictionary<int, int> GetPartitionStats() 
    {
        lock (_partitionStats) return new Dictionary<int, int>(_partitionStats);
    }

    public Dictionary<string, int> GetCustomerPartitionMap() 
    {
        lock (_customerPartitionMap) return new Dictionary<string, int>(_customerPartitionMap);
    }

    public void Dispose()
    {
        _producer?.Flush(TimeSpan.FromSeconds(10));
        _producer?.Dispose();
    }
}
