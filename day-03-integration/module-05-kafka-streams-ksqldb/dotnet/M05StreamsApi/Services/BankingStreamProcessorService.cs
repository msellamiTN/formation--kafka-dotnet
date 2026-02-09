using System.Text.Json;
using Confluent.Kafka;
using M05StreamsApi.Models;

namespace M05StreamsApi.Services;

public sealed class BankingStreamProcessorService : BackgroundService
{
    private readonly ILogger<BankingStreamProcessorService> _logger;
    private readonly BankingOptions _options;
    private readonly BankingState _state;
    private readonly IProducer<string, string> _producer;

    public BankingStreamProcessorService(
        ILogger<BankingStreamProcessorService> logger,
        BankingOptions options,
        BankingState state,
        IProducer<string, string> producer)
    {
        _logger = logger;
        _options = options;
        _state = state;
        _producer = producer;
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken)
    {
        return Task.Run(() => ConsumeLoop(stoppingToken), stoppingToken);
    }

    private void ConsumeLoop(CancellationToken stoppingToken)
    {
        var config = new ConsumerConfig
        {
            BootstrapServers = _options.BootstrapServers,
            GroupId = _options.GroupId,
            ClientId = _options.ClientId,
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = false
        };

        using var consumer = new ConsumerBuilder<string, string>(config)
            .SetErrorHandler((_, e) => _logger.LogWarning("Kafka consumer error: {Reason}", e.Reason))
            .Build();

        consumer.Subscribe(_options.TransactionsTopic);

        _logger.LogInformation(
            "Banking stream processor started. Topic={Topic} Bootstrap={Bootstrap}",
            _options.TransactionsTopic,
            _options.BootstrapServers);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    var result = consumer.Consume(stoppingToken);
                    if (result?.Message == null)
                    {
                        continue;
                    }

                    if (!TryParseTransaction(result.Message.Value, out var tx))
                    {
                        ProduceIfPossible(_options.DlqTopic, result.Message.Key, result.Message.Value);
                        consumer.Commit(result);
                        continue;
                    }

                    if (string.IsNullOrWhiteSpace(tx.CustomerId) && !string.IsNullOrWhiteSpace(result.Message.Key))
                    {
                        tx.CustomerId = result.Message.Key;
                    }

                    if (string.IsNullOrWhiteSpace(tx.CustomerId))
                    {
                        ProduceIfPossible(_options.DlqTopic, result.Message.Key, result.Message.Value);
                        consumer.Commit(result);
                        continue;
                    }

                    ProcessTransaction(tx);

                    if (tx.Amount > 10_000)
                    {
                        ProduceIfPossible(_options.FraudAlertsTopic, tx.CustomerId, result.Message.Value);
                    }

                    consumer.Commit(result);
                }
                catch (ConsumeException e)
                {
                    _logger.LogWarning(e, "Consume exception: {Reason}", e.Error.Reason);
                }
                catch (KafkaException e)
                {
                    _logger.LogWarning(e, "Kafka exception");
                }
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            try
            {
                consumer.Close();
            }
            catch
            {
            }
        }
    }

    private void ProcessTransaction(Transaction tx)
    {
        var change = GetBalanceChange(tx);
        var balance = _state.GetOrCreate(tx.CustomerId);

        lock (balance)
        {
            balance.Balance += change;
            balance.TransactionCount++;
            balance.LastUpdated = DateTime.UtcNow;
            balance.LastTransactionId = tx.TransactionId;
        }

        var payload = JsonSerializer.Serialize(balance);
        ProduceIfPossible(_options.BalancesTopic, tx.CustomerId, payload);
    }

    private void ProduceIfPossible(string topic, string? key, string? value)
    {
        if (string.IsNullOrWhiteSpace(topic) || string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        _producer.Produce(topic, new Message<string, string>
        {
            Key = key ?? string.Empty,
            Value = value
        });
    }

    private static bool TryParseTransaction(string? json, out Transaction tx)
    {
        tx = new Transaction();
        if (string.IsNullOrWhiteSpace(json))
        {
            return false;
        }

        try
        {
            var parsed = JsonSerializer.Deserialize<Transaction>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (parsed == null)
            {
                return false;
            }

            tx = parsed;
            return tx.Amount > 0;
        }
        catch
        {
            return false;
        }
    }

    private static decimal GetBalanceChange(Transaction tx)
    {
        return tx.Type switch
        {
            3 or 1 when tx.Amount > 0 => tx.Amount,
            4 or 5 or 7 => -tx.Amount,
            _ => tx.Amount
        };
    }
}
