using Confluent.Kafka;

namespace KafkaTests.Services;

public class MessageConsumer : IDisposable
{
    private readonly IConsumer<string, string> _consumer;

    public MessageConsumer(IConsumer<string, string> consumer)
    {
        _consumer = consumer;
    }

    public List<string> PollAndProcess(int maxMessages = 10, TimeSpan? timeout = null)
    {
        var processed = new List<string>();
        var pollTimeout = timeout ?? TimeSpan.FromSeconds(5);
        var deadline = DateTime.UtcNow + pollTimeout;

        while (processed.Count < maxMessages && DateTime.UtcNow < deadline)
        {
            var result = _consumer.Consume(TimeSpan.FromMilliseconds(500));
            if (result == null) continue;

            processed.Add(result.Message.Value);
        }

        return processed;
    }

    public void Dispose()
    {
        _consumer?.Close();
        _consumer?.Dispose();
    }
}
