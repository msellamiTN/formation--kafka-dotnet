using System.Collections.Concurrent;
using System.Text.Json;
using Confluent.Kafka;
using M05StreamsApi.Models;

namespace M05StreamsApi.Services;

public sealed class SalesStreamProcessorService : BackgroundService
{
    private readonly ILogger<SalesStreamProcessorService> _logger;
    private readonly StreamsOptions _options;
    private readonly StreamsState _state;
    private readonly IProducer<string, string> _producer;

    private readonly ConcurrentDictionary<string, SaleAggregate> _salesPerMinute = new(StringComparer.Ordinal);

    public SalesStreamProcessorService(
        ILogger<SalesStreamProcessorService> logger,
        StreamsOptions options,
        StreamsState state,
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

        consumer.Subscribe(_options.InputTopic);

        _logger.LogInformation(
            "Sales stream processor started. InputTopic={Topic} Bootstrap={Bootstrap}",
            _options.InputTopic,
            _options.BootstrapServers);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                ConsumeResult<string, string>? result = null;
                try
                {
                    result = consumer.Consume(stoppingToken);
                    if (result?.Message == null)
                    {
                        continue;
                    }

                    var key = result.Message.Key;
                    var value = result.Message.Value;

                    if (!TryParseSale(value, out var sale))
                    {
                        consumer.Commit(result);
                        continue;
                    }

                    if (string.IsNullOrWhiteSpace(sale.ProductId) && !string.IsNullOrWhiteSpace(key))
                    {
                        sale.ProductId = key;
                    }

                    if (string.IsNullOrWhiteSpace(sale.ProductId))
                    {
                        consumer.Commit(result);
                        continue;
                    }

                    ProcessSale(sale, value);

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

    private void ProcessSale(Sale sale, string rawSaleJson)
    {
        var productId = sale.ProductId;

        if (sale.TotalAmount > 100)
        {
            _producer.Produce(_options.LargeSalesTopic, new Message<string, string>
            {
                Key = productId,
                Value = rawSaleJson
            });
        }

        var aggregate = _state.GetOrCreateAggregate(productId);
        lock (aggregate)
        {
            aggregate.Add(sale);
        }

        var aggregateJson = JsonSerializer.Serialize(aggregate);
        _producer.Produce(_options.OutputTopic, new Message<string, string>
        {
            Key = productId,
            Value = aggregateJson
        });

        var (windowKey, minuteAggregate) = UpdateMinuteAggregation(sale);
        var minuteJson = JsonSerializer.Serialize(minuteAggregate);
        _producer.Produce(_options.SalesPerMinuteTopic, new Message<string, string>
        {
            Key = windowKey,
            Value = minuteJson
        });

        var product = _state.TryGetProduct(productId);
        if (product != null)
        {
            var productJson = JsonSerializer.Serialize(product);
            var enriched = $"{{\"sale\":{rawSaleJson},\"product\":{productJson}}}";
            _producer.Produce(_options.EnrichedSalesTopic, new Message<string, string>
            {
                Key = productId,
                Value = enriched
            });
        }

        CleanupMinuteAggregation();
    }

    private (string windowKey, SaleAggregate agg) UpdateMinuteAggregation(Sale sale)
    {
        var ts = sale.Timestamp > 0 ? sale.Timestamp : DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var start = ts - (ts % 60_000);
        var end = start + 60_000;
        var windowKey = $"{start}-{end}";

        var agg = _salesPerMinute.GetOrAdd(windowKey, _ => new SaleAggregate());
        lock (agg)
        {
            agg.Add(sale);
        }

        return (windowKey, agg);
    }

    private void CleanupMinuteAggregation()
    {
        var now = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var cutoff = now - (5 * 60_000);

        foreach (var kv in _salesPerMinute)
        {
            if (!TryParseWindowStart(kv.Key, out var start))
            {
                continue;
            }

            if (start < cutoff)
            {
                _salesPerMinute.TryRemove(kv.Key, out _);
            }
        }
    }

    private static bool TryParseWindowStart(string key, out long start)
    {
        start = 0;
        var idx = key.IndexOf('-', StringComparison.Ordinal);
        if (idx <= 0)
        {
            return false;
        }

        return long.TryParse(key[..idx], out start);
    }

    private static bool TryParseSale(string? json, out Sale sale)
    {
        sale = new Sale();
        if (string.IsNullOrWhiteSpace(json))
        {
            return false;
        }

        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            sale.ProductId = root.TryGetProperty("productId", out var productId) ? productId.GetString() ?? string.Empty : string.Empty;
            sale.Quantity = root.TryGetProperty("quantity", out var qty) && qty.TryGetInt32(out var q) ? q : 0;
            sale.UnitPrice = root.TryGetProperty("unitPrice", out var unitPrice) && unitPrice.TryGetDecimal(out var p) ? p : 0m;

            if (root.TryGetProperty("timestamp", out var timestamp))
            {
                sale.Timestamp = timestamp.ValueKind switch
                {
                    JsonValueKind.Number => timestamp.TryGetInt64(out var n) ? n : 0,
                    JsonValueKind.String => DateTimeOffset.TryParse(timestamp.GetString(), out var dto) ? dto.ToUnixTimeMilliseconds() : 0,
                    _ => 0
                };
            }

            if (sale.Timestamp == 0)
            {
                sale.Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            }

            return sale.Quantity > 0;
        }
        catch
        {
            return false;
        }
    }
}
