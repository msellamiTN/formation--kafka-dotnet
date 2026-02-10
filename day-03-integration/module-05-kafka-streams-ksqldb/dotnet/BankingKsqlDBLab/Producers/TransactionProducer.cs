using Confluent.Kafka;
using BankingKsqlDBLab.Models;
using System.Text.Json;

namespace BankingKsqlDBLab.Producers;

public class TransactionProducer : IDisposable
{
    private readonly IProducer<string, string> _producer;
    private readonly Random _random = new();
    private readonly ILogger<TransactionProducer> _logger;

    private readonly string[] _merchants =
        { "WALMART", "AMAZON", "SHELL", "CASINO_VEGAS", "STARBUCKS",
          "APPLE_STORE", "GAMBLING_ONLINE", "BOOKING_COM", "NETFLIX" };

    private readonly string[] _countries = { "FR", "US", "UK", "DE", "ES", "IT", "CA", "JP" };
    private readonly string[] _accountIds = { "ACC001", "ACC002", "ACC003", "ACC004", "ACC005" };

    public TransactionProducer(string bootstrapServers, ILogger<TransactionProducer> logger)
    {
        _logger = logger;
        var config = new ProducerConfig
        {
            BootstrapServers = bootstrapServers,
            Acks = Acks.All,
            MessageSendMaxRetries = 3
        };
        _producer = new ProducerBuilder<string, string>(config).Build();
    }

    public async Task ProduceTransactionsAsync(int count, CancellationToken cancellationToken)
    {
        _logger.LogInformation("Producing {Count} transactions...", count);

        for (int i = 0; i < count; i++)
        {
            if (cancellationToken.IsCancellationRequested) break;

            var transaction = GenerateTransaction();
            var json = JsonSerializer.Serialize(transaction);

            try
            {
                await _producer.ProduceAsync("transactions",
                    new Message<string, string>
                    {
                        Key = transaction.AccountId,
                        Value = json
                    }, cancellationToken);

                _logger.LogInformation("TXN {Index}: {Id} | {Account} | ${Amount:F2} | {Type}",
                    i + 1, transaction.TransactionId, transaction.AccountId, transaction.Amount, transaction.Type);
            }
            catch (ProduceException<string, string> ex)
            {
                _logger.LogError(ex, "Error producing transaction");
            }

            await Task.Delay(300, cancellationToken);
        }

        _producer.Flush(cancellationToken);
        _logger.LogInformation("Production complete!");
    }

    public async Task<DeliveryResult<string, string>> ProduceSingleAsync(Transaction transaction)
    {
        var json = JsonSerializer.Serialize(transaction);
        return await _producer.ProduceAsync("transactions",
            new Message<string, string>
            {
                Key = transaction.AccountId,
                Value = json
            });
    }

    private Transaction GenerateTransaction()
    {
        var accountId = _accountIds[_random.Next(_accountIds.Length)];
        var type = _random.NextDouble() > 0.4 ? "DEBIT" : "CREDIT";
        var amount = (decimal)(_random.NextDouble() * 5000 + 10);

        // Occasionally generate suspicious transactions
        if (_random.NextDouble() < 0.2)
        {
            amount = (decimal)(_random.NextDouble() * 20000 + 5000);
        }

        var merchant = _merchants[_random.Next(_merchants.Length)];

        // Suspicious merchant
        if (_random.NextDouble() < 0.1)
        {
            merchant = _random.NextDouble() > 0.5 ? "CASINO_VEGAS" : "GAMBLING_ONLINE";
        }

        return new Transaction
        {
            TransactionId = $"TXN-{Guid.NewGuid().ToString()[..8]}",
            AccountId = accountId,
            Amount = Math.Round(amount, 2),
            TransactionTime = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            Type = type,
            Merchant = merchant,
            Country = _countries[_random.Next(_countries.Length)],
            IsOnline = _random.NextDouble() > 0.2
        };
    }

    public void Dispose() => _producer?.Dispose();
}
