using System.Text.Json;
using Confluent.Kafka;
using M05StreamsApi.Models;

namespace M05StreamsApi.Services;

public sealed class ProductsConsumerService : BackgroundService
{
    private readonly ILogger<ProductsConsumerService> _logger;
    private readonly StreamsOptions _options;
    private readonly StreamsState _state;

    public ProductsConsumerService(
        ILogger<ProductsConsumerService> logger,
        StreamsOptions options,
        StreamsState state)
    {
        _logger = logger;
        _options = options;
        _state = state;
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
            GroupId = $"{_options.GroupId}-products",
            AutoOffsetReset = AutoOffsetReset.Earliest,
            EnableAutoCommit = true,
            ClientId = $"{_options.ClientId}-products"
        };

        using var consumer = new ConsumerBuilder<string, string>(config)
            .SetErrorHandler((_, e) => _logger.LogWarning("Kafka consumer error: {Reason}", e.Reason))
            .Build();

        consumer.Subscribe(_options.ProductsTopic);

        _logger.LogInformation(
            "Products consumer started. Topic={Topic} Bootstrap={Bootstrap}",
            _options.ProductsTopic,
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

                    if (string.IsNullOrWhiteSpace(result.Message.Value))
                    {
                        continue;
                    }

                    if (TryParseProduct(result.Message.Key, result.Message.Value, out var product))
                    {
                        _state.UpsertProduct(product);
                    }
                }
                catch (ConsumeException e)
                {
                    _logger.LogWarning(e, "Consume exception: {Reason}", e.Error.Reason);
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

    private static bool TryParseProduct(string? key, string value, out Product product)
    {
        product = new Product();

        try
        {
            var parsed = JsonSerializer.Deserialize<Product>(value, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (parsed == null)
            {
                return false;
            }

            if (!string.IsNullOrWhiteSpace(key))
            {
                parsed.Id = key;
            }

            if (string.IsNullOrWhiteSpace(parsed.Id))
            {
                return false;
            }

            product = parsed;
            return true;
        }
        catch
        {
            return false;
        }
    }
}
