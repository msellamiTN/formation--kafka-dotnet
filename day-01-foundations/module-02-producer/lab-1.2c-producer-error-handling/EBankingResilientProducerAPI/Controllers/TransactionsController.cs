using Microsoft.AspNetCore.Mvc;
using EBankingResilientProducerAPI.Models;
using EBankingResilientProducerAPI.Services;

namespace EBankingResilientProducerAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class TransactionsController : ControllerBase
{
    private readonly ResilientKafkaProducerService _kafka;
    private readonly ILogger<TransactionsController> _logger;

    public TransactionsController(ResilientKafkaProducerService kafka, ILogger<TransactionsController> logger)
    {
        _kafka = kafka;
        _logger = logger;
    }

    /// <summary>
    /// Créer une transaction avec gestion d'erreurs complète (retry + DLQ + circuit breaker)
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(TransactionResult), StatusCodes.Status201Created)]
    [ProducesResponseType(typeof(TransactionResult), StatusCodes.Status202Accepted)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(TransactionResult), StatusCodes.Status500InternalServerError)]
    public async Task<ActionResult<TransactionResult>> CreateTransaction(
        [FromBody] Transaction transaction, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(transaction.TransactionId))
            transaction.TransactionId = Guid.NewGuid().ToString();

        var result = await _kafka.SendTransactionAsync(transaction, ct);

        return result.Status switch
        {
            "Processing" => CreatedAtAction(nameof(GetTransaction),
                new { transactionId = result.TransactionId }, result),
            "SentToDLQ" => Accepted(result),
            _ => StatusCode(500, result)
        };
    }

    /// <summary>
    /// Envoyer un lot de transactions avec gestion d'erreurs
    /// </summary>
    [HttpPost("batch")]
    [ProducesResponseType(typeof(BatchResilientResponse), StatusCodes.Status201Created)]
    public async Task<ActionResult<BatchResilientResponse>> CreateBatch(
        [FromBody] List<Transaction> transactions, CancellationToken ct)
    {
        var results = new List<TransactionResult>();

        foreach (var tx in transactions)
        {
            if (string.IsNullOrEmpty(tx.TransactionId))
                tx.TransactionId = Guid.NewGuid().ToString();

            results.Add(await _kafka.SendTransactionAsync(tx, ct));
        }

        var response = new BatchResilientResponse
        {
            TotalCount = results.Count,
            SuccessCount = results.Count(r => r.Status == "Processing"),
            DlqCount = results.Count(r => r.Status == "SentToDLQ"),
            FailedCount = results.Count(r => r.Status == "Failed"),
            Transactions = results
        };

        return Created("", response);
    }

    /// <summary>
    /// Obtenir les métriques du producer (erreurs, DLQ, circuit breaker)
    /// </summary>
    [HttpGet("metrics")]
    [ProducesResponseType(typeof(ProducerMetrics), StatusCodes.Status200OK)]
    public ActionResult<ProducerMetrics> GetMetrics()
    {
        return Ok(_kafka.GetMetrics());
    }

    /// <summary>
    /// Obtenir le statut d'une transaction (placeholder)
    /// </summary>
    [HttpGet("{transactionId}")]
    [ProducesResponseType(typeof(TransactionResult), StatusCodes.Status200OK)]
    public ActionResult<TransactionResult> GetTransaction(string transactionId)
    {
        return Ok(new TransactionResult
        {
            TransactionId = transactionId,
            Status = "Processing",
            Timestamp = DateTime.UtcNow
        });
    }

    /// <summary>
    /// Health check avec état du circuit breaker
    /// </summary>
    [HttpGet("health")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public ActionResult GetHealth()
    {
        var metrics = _kafka.GetMetrics();
        return Ok(new
        {
            Status = metrics.CircuitBreakerOpen ? "Degraded" : "Healthy",
            Service = "EBanking Resilient Producer API",
            CircuitBreaker = metrics.CircuitBreakerOpen ? "OPEN" : "CLOSED",
            ConsecutiveFailures = metrics.ConsecutiveFailures,
            SuccessRate = $"{metrics.SuccessRate:F1}%",
            Timestamp = DateTime.UtcNow
        });
    }
}

public class BatchResilientResponse
{
    public int TotalCount { get; set; }
    public int SuccessCount { get; set; }
    public int DlqCount { get; set; }
    public int FailedCount { get; set; }
    public List<TransactionResult> Transactions { get; set; } = new();
}
