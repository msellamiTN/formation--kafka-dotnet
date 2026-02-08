using Microsoft.AspNetCore.Mvc;
using EBankingAuditAPI.Services;
using EBankingAuditAPI.Models;

namespace EBankingAuditAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
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
    /// Get full audit log (all recorded transactions).
    /// </summary>
    [HttpGet("log")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
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
    /// Search audit record by TransactionId.
    /// </summary>
    [HttpGet("log/{transactionId}")]
    [ProducesResponseType(typeof(AuditRecord), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(object), StatusCodes.Status404NotFound)]
    public IActionResult GetAuditRecord(string transactionId)
    {
        var record = _consumerService.GetAuditRecord(transactionId);
        if (record == null)
            return NotFound(new { error = $"Transaction {transactionId} not found in audit log" });

        return Ok(record);
    }

    /// <summary>
    /// Get messages sent to Dead Letter Queue (failed transactions).
    /// </summary>
    [HttpGet("dlq")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
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
    /// Get consumer metrics (commits, duplicates, DLQ, offsets).
    /// </summary>
    [HttpGet("metrics")]
    [ProducesResponseType(typeof(AuditMetrics), StatusCodes.Status200OK)]
    public IActionResult GetMetrics()
    {
        return Ok(_consumerService.GetMetrics());
    }

    /// <summary>
    /// Service health check including manual commit count.
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
            Service = "E-Banking Audit & Compliance API",
            ConsumerStatus = metrics.ConsumerStatus,
            MessagesProcessed = metrics.MessagesConsumed,
            AuditRecords = metrics.AuditRecordsCreated,
            ManualCommits = metrics.ManualCommits,
            DuplicatesSkipped = metrics.DuplicatesSkipped,
            DlqMessages = metrics.MessagesSentToDlq,
            LastCommitAt = metrics.LastCommitAt,
            Uptime = DateTime.UtcNow - metrics.StartedAt
        };

        return isHealthy ? Ok(status) : StatusCode(503, status);
    }
}
