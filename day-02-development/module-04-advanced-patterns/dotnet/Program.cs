using Confluent.Kafka;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

var bootstrapServers = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP_SERVERS") ?? "localhost:9092";
var topic = Environment.GetEnvironmentVariable("KAFKA_TOPIC") ?? "orders";
var groupId = Environment.GetEnvironmentVariable("KAFKA_GROUP_ID") ?? "orders-consumer-group";
var autoOffsetReset = Environment.GetEnvironmentVariable("KAFKA_AUTO_OFFSET_RESET") ?? "earliest";

var consumerConfig = new ConsumerConfig
{
    BootstrapServers = bootstrapServers,
    GroupId = groupId,
    AutoOffsetReset = Enum.Parse<AutoOffsetReset>(autoOffsetReset, true),
    EnableAutoCommit = false,
    SessionTimeoutMs = 45000,
    HeartbeatIntervalMs = 15000,
    MaxPollIntervalMs = 300000,
    PartitionAssignmentStrategy = PartitionAssignmentStrategy.CooperativeSticky
};

var messagesProcessed = 0L;
var partitionsAssigned = new List<string>();
var lastRebalanceTime = DateTime.MinValue;
var rebalanceCount = 0;
var cts = new CancellationTokenSource();

Task.Run(() => ConsumeMessages(cts.Token));

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "UP" }));

app.MapGet("/api/v1/stats", () => Results.Ok(new
{
    messagesProcessed,
    partitionsAssigned,
    rebalanceCount,
    lastRebalanceTime = lastRebalanceTime == DateTime.MinValue ? "N/A" : lastRebalanceTime.ToString("O")
}));

app.MapGet("/api/v1/partitions", () => Results.Ok(new
{
    partitions = partitionsAssigned,
    count = partitionsAssigned.Count
}));

app.Run();

async Task ConsumeMessages(CancellationToken cancellationToken)
{
    using var consumer = new ConsumerBuilder<string, string>(consumerConfig)
        .SetPartitionsAssignedHandler((c, partitions) =>
        {
            rebalanceCount++;
            lastRebalanceTime = DateTime.UtcNow;
            partitionsAssigned = partitions.Select(p => $"{p.Topic}-{p.Partition}").ToList();
            Console.WriteLine($"[REBALANCE] Partitions assigned: {string.Join(", ", partitionsAssigned)}");
        })
        .SetPartitionsRevokedHandler((c, partitions) =>
        {
            var revoked = partitions.Select(p => $"{p.Topic}-{p.Partition}").ToList();
            Console.WriteLine($"[REBALANCE] Partitions revoked: {string.Join(", ", revoked)}");
            try
            {
                c.Commit();
                Console.WriteLine("[REBALANCE] Offsets committed before revocation");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[REBALANCE] Error committing offsets: {ex.Message}");
            }
        })
        .SetPartitionsLostHandler((c, partitions) =>
        {
            var lost = partitions.Select(p => $"{p.Topic}-{p.Partition}").ToList();
            Console.WriteLine($"[REBALANCE] Partitions lost: {string.Join(", ", lost)}");
        })
        .Build();

    consumer.Subscribe(topic);
    Console.WriteLine($"[CONSUMER] Subscribed to topic: {topic}");
    Console.WriteLine($"[CONSUMER] Group ID: {groupId}");
    Console.WriteLine($"[CONSUMER] Bootstrap servers: {bootstrapServers}");

    while (!cancellationToken.IsCancellationRequested)
    {
        try
        {
            var consumeResult = consumer.Consume(TimeSpan.FromMilliseconds(1000));
            
            if (consumeResult == null) continue;

            Console.WriteLine($"[MESSAGE] Key: {consumeResult.Message.Key}, " +
                            $"Partition: {consumeResult.Partition}, " +
                            $"Offset: {consumeResult.Offset}");

            // Simulate processing
            await Task.Delay(100, cancellationToken);

            consumer.Commit(consumeResult);
            Interlocked.Increment(ref messagesProcessed);
        }
        catch (ConsumeException ex)
        {
            Console.WriteLine($"[ERROR] Consume error: {ex.Error.Reason}");
        }
        catch (OperationCanceledException)
        {
            break;
        }
    }

    consumer.Close();
}
