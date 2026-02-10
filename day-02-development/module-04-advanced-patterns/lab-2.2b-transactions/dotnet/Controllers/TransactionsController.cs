using Microsoft.AspNetCore.Mvc;
using EBankingTransactionsAPI.Models;
using EBankingTransactionsAPI.Services;

namespace EBankingTransactionsAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TransactionsController : ControllerBase
{
    private readonly TransactionalProducerService _producer;
    private readonly ILogger<TransactionsController> _logger;

    public TransactionsController(
        TransactionalProducerService producer,
        ILogger<TransactionsController> logger)
    {
        _producer = producer;
        _logger = logger;
    }

    /// <summary>
    /// Send a single transaction with exactly-once semantics
    /// </summary>
    [HttpPost("single")]
    public async Task<IActionResult> SendSingle([FromBody] Transaction transaction)
    {
        if (string.IsNullOrWhiteSpace(transaction.TransactionId))
            transaction.TransactionId = $"TX-EOS-{Guid.NewGuid().ToString()[..8]}";
        
        transaction.Timestamp = DateTime.UtcNow;

        var result = await _producer.SendTransactionAsync(transaction);
        
        return result.Status == "Produced" 
            ? Ok(result) 
            : StatusCode(500, result);
    }

    /// <summary>
    /// Send multiple transactions in a single atomic transaction
    /// </summary>
    [HttpPost("batch")]
    public async Task<IActionResult> SendBatch([FromBody] TransactionRequest request)
    {
        if (request.Transactions == null || !request.Transactions.Any())
            return BadRequest(new { error = "No transactions provided" });

        // Generate IDs and timestamps
        foreach (var tx in request.Transactions)
        {
            if (string.IsNullOrWhiteSpace(tx.TransactionId))
                tx.TransactionId = $"TX-EOS-{Guid.NewGuid().ToString()[..8]}";
            tx.Timestamp = DateTime.UtcNow;
        }

        var results = await _producer.SendTransactionBatchAsync(request.Transactions);
        
        var successCount = results.Count(r => r.Status == "Produced");
        var failureCount = results.Count(r => r.Status == "Failed");

        return Ok(new
        {
            totalCount = results.Count,
            successCount = successCount,
            failureCount = failureCount,
            transactionalId = results.FirstOrDefault()?.TransactionalId,
            results = results
        });
    }

    /// <summary>
    /// Get transactional producer metrics
    /// </summary>
    [HttpGet("metrics")]
    public IActionResult GetMetrics()
    {
        return Ok(_producer.GetMetrics());
    }

    /// <summary>
    /// Health check
    /// </summary>
    [HttpGet("health")]
    public IActionResult GetHealth()
    {
        var metrics = _producer.GetMetrics();
        var isHealthy = metrics.ProducerState != "Error";

        return Ok(new
        {
            status = isHealthy ? "Healthy" : "Unhealthy",
            service = "EBanking Transactional Producer API",
            transactionalId = metrics.TransactionalId,
            producerState = metrics.ProducerState,
            activeTransactions = metrics.ActiveTransactions,
            timestamp = DateTime.UtcNow
        });
    }
}
