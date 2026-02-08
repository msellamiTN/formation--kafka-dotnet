using Confluent.Kafka;
using KafkaTests.Services;
using Moq;

namespace KafkaTests.Unit;

public class ProducerUnitTest
{
    [Fact]
    public async Task SendAsync_ValidMessage_ProducesToCorrectTopic()
    {
        // Arrange
        var mockProducer = new Mock<IProducer<string, string>>();
        var capturedMessages = new List<(string Topic, Message<string, string> Message)>();

        mockProducer.Setup(p => p.ProduceAsync(
            It.IsAny<string>(),
            It.IsAny<Message<string, string>>(),
            It.IsAny<CancellationToken>()))
            .Callback<string, Message<string, string>, CancellationToken>(
                (topic, msg, ct) => capturedMessages.Add((topic, msg)))
            .ReturnsAsync(new DeliveryResult<string, string>
            {
                Topic = "test-topic",
                Partition = 0,
                Offset = 0
            });

        var producer = new MessageProducer(mockProducer.Object);

        // Act
        var result = await producer.SendAsync("test-topic", "key-1", "value-1");

        // Assert
        Assert.Single(capturedMessages);
        Assert.Equal("test-topic", capturedMessages[0].Topic);
        Assert.Equal("key-1", capturedMessages[0].Message.Key);
        Assert.Equal("value-1", capturedMessages[0].Message.Value);
    }

    [Fact]
    public async Task SendAsync_IncludesCorrelationIdHeader()
    {
        // Arrange
        var mockProducer = new Mock<IProducer<string, string>>();
        Headers? capturedHeaders = null;

        mockProducer.Setup(p => p.ProduceAsync(
            It.IsAny<string>(),
            It.IsAny<Message<string, string>>(),
            It.IsAny<CancellationToken>()))
            .Callback<string, Message<string, string>, CancellationToken>(
                (topic, msg, ct) => capturedHeaders = msg.Headers)
            .ReturnsAsync(new DeliveryResult<string, string>());

        var producer = new MessageProducer(mockProducer.Object);

        // Act
        await producer.SendAsync("test-topic", "key-1", "value-1");

        // Assert
        Assert.NotNull(capturedHeaders);
        var correlationHeader = capturedHeaders.FirstOrDefault(h => h.Key == "correlation-id");
        Assert.NotNull(correlationHeader);

        var correlationId = System.Text.Encoding.UTF8.GetString(correlationHeader.GetValueBytes());
        Assert.True(Guid.TryParse(correlationId, out _), "correlation-id should be a valid GUID");
    }

    [Fact]
    public async Task SendAsync_ProduceException_Propagates()
    {
        // Arrange
        var mockProducer = new Mock<IProducer<string, string>>();

        mockProducer.Setup(p => p.ProduceAsync(
            It.IsAny<string>(),
            It.IsAny<Message<string, string>>(),
            It.IsAny<CancellationToken>()))
            .ThrowsAsync(new ProduceException<string, string>(
                new Error(ErrorCode.BrokerNotAvailable, "Broker not available"),
                new DeliveryResult<string, string>()));

        var producer = new MessageProducer(mockProducer.Object);

        // Act & Assert
        await Assert.ThrowsAsync<ProduceException<string, string>>(
            () => producer.SendAsync("test-topic", "key-1", "value-1"));
    }

    [Fact]
    public async Task SendAsync_MultipleCalls_AllCaptured()
    {
        // Arrange
        var mockProducer = new Mock<IProducer<string, string>>();

        mockProducer.Setup(p => p.ProduceAsync(
            It.IsAny<string>(),
            It.IsAny<Message<string, string>>(),
            It.IsAny<CancellationToken>()))
            .ReturnsAsync(new DeliveryResult<string, string>());

        var producer = new MessageProducer(mockProducer.Object);

        // Act
        await producer.SendAsync("topic-a", "key-1", "value-1");
        await producer.SendAsync("topic-a", "key-2", "value-2");
        await producer.SendAsync("topic-a", "key-3", "value-3");

        // Assert
        mockProducer.Verify(p => p.ProduceAsync(
            "topic-a",
            It.IsAny<Message<string, string>>(),
            It.IsAny<CancellationToken>()), Times.Exactly(3));
    }
}
