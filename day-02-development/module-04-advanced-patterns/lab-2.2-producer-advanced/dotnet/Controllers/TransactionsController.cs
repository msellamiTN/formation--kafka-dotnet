using Microsoft.AspNetCore.Mvc;
using EBankingIdempotentProducerAPI.Models;
using EBankingIdempotentProducerAPI.Services;

namespace EBankingIdempotentProducerAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TransactionsController : ControllerBase
{
    private readonly IdempotentProducerService _idempotent;
    private readonly NonIdempotentProducerService _nonIdempotent;
    private readonly ILogger<TransactionsController> _logger;

    public TransactionsController(
        IdempotentProducerService idempotent,
        NonIdempotentProducerService nonIdempotent,
        ILogger<TransactionsController> logger)
    {
        _idempotent = idempotent;
        _nonIdempotent = nonIdempotent;
        _logger = logger;
    }

    /// <summary>
    /// Send a transaction using the IDEMPOTENT producer (EnableIdempotence=true).
    /// The broker assigns a PID and tracks sequence numbers to deduplicate retries.
    /// </summary>
    [HttpPost("idempotent")]
    public async Task<IActionResult> SendIdempotent([FromBody] Transaction tx)
    {
        if (string.IsNullOrWhiteSpace(tx.TransactionId))
            tx.TransactionId = $"TX-IDEM-{Guid.NewGuid().ToString()[..8]}";
        tx.Timestamp = DateTime.UtcNow;

        var result = await _idempotent.SendAsync(tx);
        return result.Status == "Produced" ? Ok(result) : StatusCode(500, result);
    }

    /// <summary>
    /// Send a transaction using the NON-IDEMPOTENT producer (EnableIdempotence=false).
    /// Retries may create duplicates if the ACK is lost after the broker writes.
    /// </summary>
    [HttpPost("non-idempotent")]
    public async Task<IActionResult> SendNonIdempotent([FromBody] Transaction tx)
    {
        if (string.IsNullOrWhiteSpace(tx.TransactionId))
            tx.TransactionId = $"TX-NOID-{Guid.NewGuid().ToString()[..8]}";
        tx.Timestamp = DateTime.UtcNow;

        var result = await _nonIdempotent.SendAsync(tx);
        return result.Status == "Produced" ? Ok(result) : StatusCode(500, result);
    }

    /// <summary>
    /// Send a batch of transactions through BOTH producers for comparison.
    /// Each transaction gets a unique ID and is sent to both producers.
    /// </summary>
    [HttpPost("batch")]
    public async Task<IActionResult> SendBatch([FromBody] BatchRequest request)
    {
        var count = Math.Min(request.Count, 100);
        var idempotentResults = new List<ProduceResultDto>();
        var nonIdempotentResults = new List<ProduceResultDto>();

        for (int i = 1; i <= count; i++)
        {
            var baseTx = new Transaction
            {
                CustomerId = request.CustomerId,
                FromAccount = "FR7630001000123456789",
                ToAccount = "FR7630001000987654321",
                Amount = 100m + i * 10,
                Currency = "EUR",
                Type = 1,
                Timestamp = DateTime.UtcNow
            };

            // Idempotent
            var idemTx = baseTx with { TransactionId = $"TX-BATCH-IDEM-{i:D3}" };
            idempotentResults.Add(await _idempotent.SendAsync(idemTx));

            // Non-idempotent
            var nonTx = baseTx with { TransactionId = $"TX-BATCH-NOID-{i:D3}" };
            nonIdempotentResults.Add(await _nonIdempotent.SendAsync(nonTx));
        }

        return Ok(new
        {
            batchSize = count,
            idempotent = new
            {
                produced = idempotentResults.Count(r => r.Status == "Produced"),
                failed = idempotentResults.Count(r => r.Status == "Failed"),
                config = "EnableIdempotence=true, Acks=All",
                duplicateRisk = "NONE — PID + sequence numbers prevent duplicates",
                results = idempotentResults
            },
            nonIdempotent = new
            {
                produced = nonIdempotentResults.Count(r => r.Status == "Produced"),
                failed = nonIdempotentResults.Count(r => r.Status == "Failed"),
                config = "EnableIdempotence=false, Acks=Leader",
                duplicateRisk = "YES — retries after lost ACK create duplicates",
                results = nonIdempotentResults
            }
        });
    }

    /// <summary>
    /// Metrics for both producers: message counts, config, PID info.
    /// </summary>
    [HttpGet("metrics")]
    public IActionResult GetMetrics()
    {
        return Ok(new
        {
            idempotentProducer = _idempotent.GetMetrics(),
            nonIdempotentProducer = _nonIdempotent.GetMetrics()
        });
    }

    /// <summary>
    /// Side-by-side configuration comparison of both producers.
    /// </summary>
    [HttpGet("compare")]
    public IActionResult Compare()
    {
        return Ok(new
        {
            comparison = new[]
            {
                new { setting = "EnableIdempotence", idempotent = "true", nonIdempotent = "false", impact = "PID + sequence numbers for deduplication" },
                new { setting = "Acks", idempotent = "All (forced)", nonIdempotent = "Leader", impact = "All ISR replicas must ACK vs only leader" },
                new { setting = "MaxInFlight", idempotent = "5 (max with idempotence)", nonIdempotent = "5", impact = "Limits in-flight requests for ordering" },
                new { setting = "MaxRetries", idempotent = "int.MaxValue (forced)", nonIdempotent = "3", impact = "Infinite retries vs limited" },
                new { setting = "Duplicate risk", idempotent = "NONE", nonIdempotent = "YES on retry", impact = "Critical for banking transactions" },
                new { setting = "Performance overhead", idempotent = "~negligible", nonIdempotent = "baseline", impact = "No reason NOT to enable idempotence" }
            },
            recommendation = "ALWAYS enable EnableIdempotence=true in production. The overhead is negligible and it prevents duplicates."
        });
    }
}
