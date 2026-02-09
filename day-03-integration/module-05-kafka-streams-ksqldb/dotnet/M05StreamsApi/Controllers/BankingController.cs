using System.Text.Json;
using Confluent.Kafka;
using Microsoft.AspNetCore.Mvc;
using M05StreamsApi.Models;
using M05StreamsApi.Services;

namespace M05StreamsApi.Controllers;

[ApiController]
[Route("api/v1")]
public sealed class BankingController : ControllerBase
{
    private readonly IProducer<string, string> _producer;
    private readonly BankingOptions _options;
    private readonly BankingState _state;

    public BankingController(IProducer<string, string> producer, BankingOptions options, BankingState state)
    {
        _producer = producer;
        _options = options;
        _state = state;
    }

    [HttpPost("transactions")]
    public IActionResult CreateTransaction([FromBody] Transaction tx)
    {
        if (string.IsNullOrWhiteSpace(tx.TransactionId))
        {
            tx.TransactionId = Guid.NewGuid().ToString();
        }

        if (tx.Timestamp == default)
        {
            tx.Timestamp = DateTime.UtcNow;
        }

        if (string.IsNullOrWhiteSpace(tx.CustomerId) || tx.Amount <= 0)
        {
            return BadRequest(new { status = "ERROR", error = "customerId and amount are required" });
        }

        var key = tx.CustomerId;
        var value = JsonSerializer.Serialize(tx);

        _producer.Produce(_options.TransactionsTopic, new Message<string, string>
        {
            Key = key,
            Value = value
        });

        return Accepted(new
        {
            status = "ACCEPTED",
            topic = _options.TransactionsTopic,
            transactionId = tx.TransactionId,
            customerId = tx.CustomerId
        });
    }

    [HttpGet("balances")]
    public IActionResult GetAllBalances()
    {
        return Ok(_state.Balances);
    }

    [HttpGet("balances/{customerId}")]
    public IActionResult GetBalance(string customerId)
    {
        return _state.TryGet(customerId, out var balance) ? Ok(balance) : NotFound();
    }
}
