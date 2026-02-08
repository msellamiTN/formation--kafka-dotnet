using Microsoft.AspNetCore.Mvc;
using EBankingBalanceAPI.Services;
using EBankingBalanceAPI.Models;

namespace EBankingBalanceAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class BalanceController : ControllerBase
{
    private readonly BalanceConsumerService _consumerService;
    private readonly ILogger<BalanceController> _logger;

    public BalanceController(
        BalanceConsumerService consumerService,
        ILogger<BalanceController> logger)
    {
        _consumerService = consumerService;
        _logger = logger;
    }

    /// <summary>
    /// Get all customer balances computed from consumed transactions.
    /// </summary>
    [HttpGet("balances")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public IActionResult GetAllBalances()
    {
        var balances = _consumerService.GetAllBalances();
        return Ok(new
        {
            count = balances.Count,
            balances = balances.Values.OrderBy(b => b.CustomerId)
        });
    }

    /// <summary>
    /// Get balance for a specific customer.
    /// </summary>
    [HttpGet("balances/{customerId}")]
    [ProducesResponseType(typeof(CustomerBalance), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(object), StatusCodes.Status404NotFound)]
    public IActionResult GetBalance(string customerId)
    {
        var balance = _consumerService.GetBalance(customerId);
        if (balance == null)
            return NotFound(new { error = $"Customer {customerId} not found" });

        return Ok(balance);
    }

    /// <summary>
    /// Get Kafka consumer group metrics (partitions, offsets, rebalancing history).
    /// </summary>
    [HttpGet("metrics")]
    [ProducesResponseType(typeof(ConsumerGroupMetrics), StatusCodes.Status200OK)]
    public IActionResult GetMetrics()
    {
        return Ok(_consumerService.GetMetrics());
    }

    /// <summary>
    /// Get partition rebalancing history (assignments, revocations, losses).
    /// </summary>
    [HttpGet("rebalancing-history")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public IActionResult GetRebalancingHistory()
    {
        var metrics = _consumerService.GetMetrics();
        return Ok(new
        {
            consumerId = metrics.ConsumerId,
            currentPartitions = metrics.AssignedPartitions,
            totalRebalancingEvents = metrics.RebalancingHistory.Count,
            history = metrics.RebalancingHistory.OrderByDescending(e => e.Timestamp)
        });
    }

    /// <summary>
    /// Service health check including consumer group status.
    /// </summary>
    [HttpGet("health")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(object), StatusCodes.Status503ServiceUnavailable)]
    public IActionResult GetHealth()
    {
        var metrics = _consumerService.GetMetrics();
        var isHealthy = metrics.Status == "Consuming" || metrics.Status == "Running";

        var status = new
        {
            Status = isHealthy ? "Healthy" : "Degraded",
            Service = "E-Banking Balance API",
            ConsumerId = metrics.ConsumerId,
            ConsumerStatus = metrics.Status,
            AssignedPartitions = metrics.AssignedPartitions,
            MessagesProcessed = metrics.MessagesConsumed,
            LastMessageAt = metrics.LastMessageAt,
            Uptime = DateTime.UtcNow - metrics.StartedAt
        };

        return isHealthy ? Ok(status) : StatusCode(503, status);
    }
}
