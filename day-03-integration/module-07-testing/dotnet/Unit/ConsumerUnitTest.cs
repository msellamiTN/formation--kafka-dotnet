using Confluent.Kafka;
using KafkaTests.Services;
using Moq;

namespace KafkaTests.Unit;

public class ConsumerUnitTest
{
    [Fact]
    public void PollAndProcess_SingleMessage_ReturnsValue()
    {
        // Arrange
        var mockConsumer = new Mock<IConsumer<string, string>>();
        var callCount = 0;

        mockConsumer.Setup(c => c.Consume(It.IsAny<TimeSpan>()))
            .Returns(() =>
            {
                callCount++;
                if (callCount == 1)
                {
                    return new ConsumeResult<string, string>
                    {
                        Topic = "test-topic",
                        Partition = 0,
                        Offset = 0,
                        Message = new Message<string, string>
                        {
                            Key = "key-1",
                            Value = "{\"orderId\":\"ORD-001\",\"amount\":100}"
                        }
                    };
                }
                return null;
            });

        var consumer = new MessageConsumer(mockConsumer.Object);

        // Act
        var processed = consumer.PollAndProcess(maxMessages: 1);

        // Assert
        Assert.Single(processed);
        Assert.Contains("ORD-001", processed[0]);
    }

    [Fact]
    public void PollAndProcess_MultipleMessages_ReturnsAll()
    {
        // Arrange
        var mockConsumer = new Mock<IConsumer<string, string>>();
        var callCount = 0;

        mockConsumer.Setup(c => c.Consume(It.IsAny<TimeSpan>()))
            .Returns(() =>
            {
                callCount++;
                if (callCount <= 3)
                {
                    return new ConsumeResult<string, string>
                    {
                        Topic = "test-topic",
                        Partition = 0,
                        Offset = callCount - 1,
                        Message = new Message<string, string>
                        {
                            Key = $"key-{callCount}",
                            Value = $"value-{callCount}"
                        }
                    };
                }
                return null;
            });

        var consumer = new MessageConsumer(mockConsumer.Object);

        // Act
        var processed = consumer.PollAndProcess(maxMessages: 3);

        // Assert
        Assert.Equal(3, processed.Count);
        Assert.Equal("value-1", processed[0]);
        Assert.Equal("value-2", processed[1]);
        Assert.Equal("value-3", processed[2]);
    }

    [Fact]
    public void PollAndProcess_NoMessages_ReturnsEmpty()
    {
        // Arrange
        var mockConsumer = new Mock<IConsumer<string, string>>();

        mockConsumer.Setup(c => c.Consume(It.IsAny<TimeSpan>()))
            .Returns((ConsumeResult<string, string>?)null);

        var consumer = new MessageConsumer(mockConsumer.Object);

        // Act
        var processed = consumer.PollAndProcess(maxMessages: 5, timeout: TimeSpan.FromSeconds(2));

        // Assert
        Assert.Empty(processed);
    }

    [Fact]
    public void PollAndProcess_TimeoutExpires_ReturnsPartialResults()
    {
        // Arrange
        var mockConsumer = new Mock<IConsumer<string, string>>();
        var callCount = 0;

        mockConsumer.Setup(c => c.Consume(It.IsAny<TimeSpan>()))
            .Returns(() =>
            {
                callCount++;
                if (callCount == 1)
                {
                    return new ConsumeResult<string, string>
                    {
                        Topic = "test-topic",
                        Partition = 0,
                        Offset = 0,
                        Message = new Message<string, string>
                        {
                            Key = "key-1",
                            Value = "value-1"
                        }
                    };
                }
                Thread.Sleep(600);
                return null;
            });

        var consumer = new MessageConsumer(mockConsumer.Object);

        // Act
        var processed = consumer.PollAndProcess(maxMessages: 10, timeout: TimeSpan.FromSeconds(2));

        // Assert
        Assert.Single(processed);
        Assert.Equal("value-1", processed[0]);
    }
}
