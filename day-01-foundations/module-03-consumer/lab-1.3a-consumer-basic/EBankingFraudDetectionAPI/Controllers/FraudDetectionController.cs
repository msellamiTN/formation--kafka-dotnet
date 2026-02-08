using Microsoft.AspNetCore.Mvc;
using EBankingFraudDetectionAPI.Services;
using EBankingFraudDetectionAPI.Models;

namespace EBankingFraudDetectionAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class FraudDetectionController : ControllerBase
{
    private readonly KafkaConsumerService _consumerService;
    private readonly ILogger<FraudDetectionController> _logger;

    public FraudDetectionController(
        KafkaConsumerService consumerService,
        ILogger<FraudDetectionController> logger)
    {
        _consumerService = consumerService;
        _logger = logger;
    }

    /// <summary>
    /// Get all fraud alerts detected by the service.
    /// </summary>
    [HttpGet("alerts")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public IActionResult GetAlerts()
    {
        var alerts = _consumerService.GetAlerts();
        return Ok(new
        {
            count = alerts.Count,
            alerts
        });
    }

    /// <summary>
    /// Get high-risk alerts (Score >= 50).
    /// </summary>
    [HttpGet("alerts/high-risk")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public IActionResult GetHighRiskAlerts()
    {
        var alerts = _consumerService.GetHighRiskAlerts();
        return Ok(new
        {
            count = alerts.Count,
            alerts
        });
    }

    /// <summary>
    /// Get Kafka consumer metrics (lag, throughput, status).
    /// </summary>
    [HttpGet("metrics")]
    [ProducesResponseType(typeof(ConsumerMetrics), StatusCodes.Status200OK)]
    public IActionResult GetMetrics()
    {
        return Ok(_consumerService.GetMetrics());
    }

    /// <summary>
    /// Service health check including consumer status.
    /// </summary>
    [HttpGet("health")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(object), StatusCodes.Status503ServiceUnavailable)]
    public IActionResult GetHealth()
    {
        var metrics = _consumerService.GetMetrics();
        var isHealthy = metrics.ConsumerStatus == "Consuming" || metrics.ConsumerStatus == "Running";

        var status = new
        {
            Status = isHealthy ? "Healthy" : "Degraded",
            Service = "E-Banking Fraud Detection API",
            ConsumerStatus = metrics.ConsumerStatus,
            MessagesProcessed = metrics.MessagesConsumed,
            LastMessageAt = metrics.LastMessageAt,
            Uptime = DateTime.UtcNow - metrics.StartedAt
        };

        return isHealthy ? Ok(status) : StatusCode(503, status);
    }
}
