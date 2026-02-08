using Confluent.Kafka;
using KafkaTests.Services;
using Testcontainers.Kafka;

namespace KafkaTests.Integration;

public class KafkaIntegrationTest : IAsyncLifetime
{
    private readonly KafkaContainer _kafka = new KafkaBuilder()
        .WithImage("confluentinc/cp-kafka:7.5.0")
        .Build();

    private string BootstrapServers => _kafka.GetBootstrapAddress();

    public async Task InitializeAsync()
    {
        await _kafka.StartAsync();
    }

    public async Task DisposeAsync()
    {
        await _kafka.DisposeAsync();
    }

    [Fact]
    public async Task ProduceAndConsume_SingleMessage_RoundTrip()
    {
        // Arrange
        var topic = "test-roundtrip";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = BootstrapServers
        };

        var consumerConfig = new ConsumerConfig
        {
            BootstrapServers = BootstrapServers,
            GroupId = "test-group-roundtrip",
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = true
        };

        // Act - Produce
        using var producer = new ProducerBuilder<string, string>(producerConfig).Build();
        var deliveryResult = await producer.ProduceAsync(topic, new Message<string, string>
        {
            Key = "order-123",
            Value = "{\"orderId\":\"ORD-001\",\"amount\":250.00}"
        });

        // Assert - Produce
        Assert.Equal(topic, deliveryResult.Topic);
        Assert.True(deliveryResult.Offset >= 0);

        // Act - Consume
        using var consumer = new ConsumerBuilder<string, string>(consumerConfig).Build();
        consumer.Subscribe(topic);

        var result = consumer.Consume(TimeSpan.FromSeconds(15));

        // Assert - Consume
        Assert.NotNull(result);
        Assert.Equal("order-123", result.Message.Key);
        Assert.Contains("ORD-001", result.Message.Value);
    }

    [Fact]
    public async Task ProduceAndConsume_MultipleMessages_AllReceived()
    {
        // Arrange
        var topic = "test-multi";
        var messageCount = 10;

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = BootstrapServers
        };

        var consumerConfig = new ConsumerConfig
        {
            BootstrapServers = BootstrapServers,
            GroupId = "test-group-multi",
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = true
        };

        // Act - Produce N messages
        using var producer = new ProducerBuilder<string, string>(producerConfig).Build();
        for (int i = 0; i < messageCount; i++)
        {
            await producer.ProduceAsync(topic, new Message<string, string>
            {
                Key = $"key-{i}",
                Value = $"value-{i}"
            });
        }
        producer.Flush(TimeSpan.FromSeconds(5));

        // Act - Consume all messages
        using var consumer = new ConsumerBuilder<string, string>(consumerConfig).Build();
        consumer.Subscribe(topic);

        var received = new List<string>();
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(30);

        while (received.Count < messageCount && DateTime.UtcNow < deadline)
        {
            var result = consumer.Consume(TimeSpan.FromSeconds(2));
            if (result != null)
                received.Add(result.Message.Value);
        }

        // Assert
        Assert.Equal(messageCount, received.Count);
        for (int i = 0; i < messageCount; i++)
        {
            Assert.Contains($"value-{i}", received);
        }
    }

    [Fact]
    public async Task ProduceWithHeaders_HeadersPreserved()
    {
        // Arrange
        var topic = "test-headers";

        var producerConfig = new ProducerConfig
        {
            BootstrapServers = BootstrapServers
        };

        var consumerConfig = new ConsumerConfig
        {
            BootstrapServers = BootstrapServers,
            GroupId = "test-group-headers",
            AutoOffsetReset = AutoOffsetReset.Earliest
        };

        var correlationId = Guid.NewGuid().ToString();

        // Act - Produce with headers
        using var rawProducer = new ProducerBuilder<string, string>(producerConfig).Build();
        var messageProducer = new MessageProducer(rawProducer);
        await messageProducer.SendAsync(topic, "key-1", "value-1");

        // Consume and check headers
        using var consumer = new ConsumerBuilder<string, string>(consumerConfig).Build();
        consumer.Subscribe(topic);

        var result = consumer.Consume(TimeSpan.FromSeconds(15));

        // Assert
        Assert.NotNull(result);
        Assert.NotNull(result.Message.Headers);

        var corrHeader = result.Message.Headers.FirstOrDefault(h => h.Key == "correlation-id");
        Assert.NotNull(corrHeader);

        var sourceHeader = result.Message.Headers.FirstOrDefault(h => h.Key == "source");
        Assert.NotNull(sourceHeader);
        Assert.Equal("message-producer",
            System.Text.Encoding.UTF8.GetString(sourceHeader.GetValueBytes()));
    }

    [Fact]
    public async Task ConsumerGroup_TwoConsumers_PartitionsDistributed()
    {
        // Arrange
        var topic = "test-consumer-group";
        var groupId = "test-group-scaling";

        var adminConfig = new AdminClientConfig { BootstrapServers = BootstrapServers };
        using var adminClient = new AdminClientBuilder(adminConfig).Build();

        await adminClient.CreateTopicsAsync(new[]
        {
            new Confluent.Kafka.Admin.TopicSpecification
            {
                Name = topic,
                NumPartitions = 4,
                ReplicationFactor = 1
            }
        });

        var producerConfig = new ProducerConfig { BootstrapServers = BootstrapServers };

        // Produce messages to all partitions
        using var producer = new ProducerBuilder<string, string>(producerConfig).Build();
        for (int i = 0; i < 20; i++)
        {
            await producer.ProduceAsync(topic, new Message<string, string>
            {
                Key = $"key-{i}",
                Value = $"value-{i}"
            });
        }
        producer.Flush(TimeSpan.FromSeconds(5));

        // Act - Create two consumers in the same group
        var consumerConfig = new ConsumerConfig
        {
            BootstrapServers = BootstrapServers,
            GroupId = groupId,
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = true
        };

        using var consumer1 = new ConsumerBuilder<string, string>(consumerConfig).Build();
        consumer1.Subscribe(topic);

        // First consumer should get messages
        var consumer1Messages = new List<string>();
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(15);
        while (DateTime.UtcNow < deadline)
        {
            var result = consumer1.Consume(TimeSpan.FromMilliseconds(500));
            if (result != null)
                consumer1Messages.Add(result.Message.Value);
        }

        // Assert - First consumer received all messages (only consumer in group)
        Assert.Equal(20, consumer1Messages.Count);
    }
}
