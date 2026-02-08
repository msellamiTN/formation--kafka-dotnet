using Microsoft.AspNetCore.Mvc;
using EBankingBalanceAPI.Services;

namespace EBankingBalanceAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
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
    /// Récupère les soldes de tous les clients
    /// </summary>
    [HttpGet("balances")]
    [ProducesResponseType(StatusCodes.Status200OK)]
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
    /// Récupère le solde d'un client spécifique
    /// </summary>
    [HttpGet("balances/{customerId}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public IActionResult GetBalance(string customerId)
    {
        var balance = _consumerService.GetBalance(customerId);
        if (balance == null)
            return NotFound(new { error = $"Customer {customerId} not found" });

        return Ok(balance);
    }

    /// <summary>
    /// Métriques du consumer : partitions, offsets, rebalancing history
    /// </summary>
    [HttpGet("metrics")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult GetMetrics()
    {
        return Ok(_consumerService.GetMetrics());
    }

    /// <summary>
    /// Historique des rebalancing (assignations, révocations)
    /// </summary>
    [HttpGet("rebalancing-history")]
    [ProducesResponseType(StatusCodes.Status200OK)]
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
    /// Health check incluant le statut du consumer group
    /// </summary>
    [HttpGet("health")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public IActionResult GetHealth()
    {
        var metrics = _consumerService.GetMetrics();
        var isHealthy = metrics.Status == "Consuming" || metrics.Status == "Running";

        var health = new
        {
            status = isHealthy ? "Healthy" : "Degraded",
            consumerId = metrics.ConsumerId,
            consumerStatus = metrics.Status,
            assignedPartitions = metrics.AssignedPartitions,
            messagesConsumed = metrics.MessagesConsumed,
            lastMessageAt = metrics.LastMessageAt,
            uptime = DateTime.UtcNow - metrics.StartedAt
        };

        return isHealthy ? Ok(health) : StatusCode(503, health);
    }
}
