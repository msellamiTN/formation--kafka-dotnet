using Confluent.Kafka;

namespace KafkaTests.Services;

public class MessageProducer : IDisposable
{
    private readonly IProducer<string, string> _producer;

    public MessageProducer(IProducer<string, string> producer)
    {
        _producer = producer;
    }

    public async Task<DeliveryResult<string, string>> SendAsync(
        string topic, string key, string value, CancellationToken ct = default)
    {
        var message = new Message<string, string>
        {
            Key = key,
            Value = value,
            Headers = new Headers
            {
                { "correlation-id", System.Text.Encoding.UTF8.GetBytes(Guid.NewGuid().ToString()) },
                { "source", System.Text.Encoding.UTF8.GetBytes("message-producer") }
            }
        };

        return await _producer.ProduceAsync(topic, message, ct);
    }

    public void Dispose()
    {
        _producer?.Dispose();
    }
}
