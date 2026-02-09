using System.Text.Json;
using Confluent.Kafka;
using Microsoft.AspNetCore.Mvc;
using M05StreamsApi.Models;
using M05StreamsApi.Services;

namespace M05StreamsApi.Controllers;

[ApiController]
[Route("api/v1")]
public sealed class SalesController : ControllerBase
{
    private readonly IProducer<string, string> _producer;
    private readonly StreamsOptions _options;
    private readonly StreamsState _state;

    public SalesController(IProducer<string, string> producer, StreamsOptions options, StreamsState state)
    {
        _producer = producer;
        _options = options;
        _state = state;
    }

    [HttpPost("sales")]
    public IActionResult CreateSale([FromBody] Sale sale)
    {
        sale.Timestamp = sale.Timestamp == 0 ? DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() : sale.Timestamp;

        if (string.IsNullOrWhiteSpace(sale.ProductId) || sale.Quantity <= 0)
        {
            return BadRequest(new { status = "ERROR", error = "productId and quantity are required" });
        }

        var key = sale.ProductId;
        var value = JsonSerializer.Serialize(sale);

        _producer.Produce(_options.InputTopic, new Message<string, string>
        {
            Key = key,
            Value = value
        });

        return Ok(new
        {
            status = "ACCEPTED",
            productId = sale.ProductId,
            totalAmount = sale.TotalAmount,
            topic = _options.InputTopic
        });
    }

    [HttpGet("stats/by-product")]
    public IActionResult GetStatsByProduct()
    {
        var result = _state.SalesByProduct.ToDictionary(
            kv => kv.Key,
            kv => new
            {
                count = kv.Value.Count,
                totalAmount = kv.Value.TotalAmount,
                totalQuantity = kv.Value.TotalQuantity
            });

        return Ok(result);
    }

    [HttpGet("stats/per-minute")]
    public IActionResult GetStatsPerMinute()
    {
        return Ok(new
        {
            message = "Check sales-per-minute topic in Kafka UI",
            topic = _options.SalesPerMinuteTopic
        });
    }

    [HttpGet("health")]
    public IActionResult Health()
    {
        return Ok(new
        {
            status = "UP",
            store = new
            {
                salesByProduct = _state.SalesByProduct.Count,
                products = _state.Products.Count
            }
        });
    }
}
