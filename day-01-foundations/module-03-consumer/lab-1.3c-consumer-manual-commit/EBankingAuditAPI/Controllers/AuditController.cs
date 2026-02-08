using Microsoft.AspNetCore.Mvc;
using EBankingAuditAPI.Services;

namespace EBankingAuditAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuditController : ControllerBase
{
    private readonly AuditConsumerService _consumerService;
    private readonly ILogger<AuditController> _logger;

    public AuditController(
        AuditConsumerService consumerService,
        ILogger<AuditController> logger)
    {
        _consumerService = consumerService;
        _logger = logger;
    }

    /// <summary>
    /// Journal d'audit complet (toutes les transactions enregistrées)
    /// </summary>
    [HttpGet("log")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult GetAuditLog()
    {
        var records = _consumerService.GetAuditLog();
        return Ok(new
        {
            count = records.Count,
            records
        });
    }

    /// <summary>
    /// Rechercher un enregistrement d'audit par TransactionId
    /// </summary>
    [HttpGet("log/{transactionId}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public IActionResult GetAuditRecord(string transactionId)
    {
        var record = _consumerService.GetAuditRecord(transactionId);
        if (record == null)
            return NotFound(new { error = $"Transaction {transactionId} not found in audit log" });

        return Ok(record);
    }

    /// <summary>
    /// Messages envoyés en Dead Letter Queue (transactions échouées)
    /// </summary>
    [HttpGet("dlq")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult GetDlqMessages()
    {
        var messages = _consumerService.GetDlqMessages();
        return Ok(new
        {
            count = messages.Count,
            messages
        });
    }

    /// <summary>
    /// Métriques du consumer : commits, doublons, DLQ, offsets
    /// </summary>
    [HttpGet("metrics")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public IActionResult GetMetrics()
    {
        return Ok(_consumerService.GetMetrics());
    }

    /// <summary>
    /// Health check incluant le nombre de commits manuels
    /// </summary>
    [HttpGet("health")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public IActionResult GetHealth()
    {
        var metrics = _consumerService.GetMetrics();
        var isHealthy = metrics.ConsumerStatus == "Consuming" ||
                        metrics.ConsumerStatus == "Running";

        var health = new
        {
            status = isHealthy ? "Healthy" : "Degraded",
            consumerStatus = metrics.ConsumerStatus,
            messagesConsumed = metrics.MessagesConsumed,
            auditRecords = metrics.AuditRecordsCreated,
            manualCommits = metrics.ManualCommits,
            duplicatesSkipped = metrics.DuplicatesSkipped,
            dlqMessages = metrics.MessagesSentToDlq,
            lastCommitAt = metrics.LastCommitAt,
            uptime = DateTime.UtcNow - metrics.StartedAt
        };

        return isHealthy ? Ok(health) : StatusCode(503, health);
    }
}
