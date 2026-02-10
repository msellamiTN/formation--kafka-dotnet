using BankingKsqlDBLab.Services;
using BankingKsqlDBLab.Models;
using BankingKsqlDBLab.Producers;
using Microsoft.AspNetCore.Mvc;

namespace BankingKsqlDBLab.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TransactionStreamController : ControllerBase
{
    private readonly KsqlDbService _ksqlService;
    private readonly TransactionProducer _producer;
    private readonly ILogger<TransactionStreamController> _logger;

    public TransactionStreamController(
        KsqlDbService ksqlService,
        TransactionProducer producer,
        ILogger<TransactionStreamController> logger)
    {
        _ksqlService = ksqlService;
        _producer = producer;
        _logger = logger;
    }

    /// <summary>
    /// Initialize ksqlDB streams and tables
    /// </summary>
    [HttpPost("initialize")]
    public async Task<IActionResult> InitializeStreams()
    {
        try
        {
            await _ksqlService.InitializeStreamsAsync();
            return Ok(new { message = "Streams initialized successfully", timestamp = DateTime.UtcNow });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    /// <summary>
    /// Produce a single transaction to Kafka
    /// </summary>
    [HttpPost("transactions")]
    public async Task<IActionResult> ProduceTransaction([FromBody] Transaction transaction)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(transaction.TransactionId))
                transaction.TransactionId = $"TXN-{Guid.NewGuid().ToString()[..8]}";
            if (transaction.TransactionTime == 0)
                transaction.TransactionTime = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

            var result = await _producer.ProduceSingleAsync(transaction);
            return Ok(new
            {
                status = "ACCEPTED",
                transactionId = transaction.TransactionId,
                partition = result.Partition.Value,
                offset = result.Offset.Value
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    /// <summary>
    /// Produce N random test transactions
    /// </summary>
    [HttpPost("transactions/generate/{count}")]
    public async Task<IActionResult> GenerateTransactions(int count, CancellationToken ct)
    {
        if (count < 1 || count > 500)
            return BadRequest(new { error = "Count must be between 1 and 500" });

        _ = Task.Run(async () =>
        {
            try
            {
                await _producer.ProduceTransactionsAsync(count, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error generating transactions");
            }
        }, ct);

        return Accepted(new { message = $"Generating {count} transactions in background", timestamp = DateTime.UtcNow });
    }

    /// <summary>
    /// Stream verified transactions in real-time (Push Query)
    /// </summary>
    [HttpGet("verified/stream")]
    public async IAsyncEnumerable<VerifiedTransaction> StreamVerifiedTransactions(
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var transaction in _ksqlService.StreamVerifiedTransactionsAsync().WithCancellation(cancellationToken))
        {
            yield return transaction;
        }
    }

    /// <summary>
    /// Stream fraud alerts in real-time (Push Query)
    /// </summary>
    [HttpGet("fraud/stream")]
    public async IAsyncEnumerable<FraudAlert> StreamFraudAlerts(
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
    {
        await foreach (var alert in _ksqlService.StreamFraudAlertsAsync().WithCancellation(cancellationToken))
        {
            yield return alert;
        }
    }

    /// <summary>
    /// Get current account balance (Pull Query)
    /// </summary>
    [HttpGet("account/{accountId}/balance")]
    public async Task<IActionResult> GetAccountBalance(string accountId)
    {
        try
        {
            var balance = await _ksqlService.GetAccountBalanceAsync(accountId);
            if (balance == null)
                return NotFound(new { message = $"No data for account {accountId}" });

            return Ok(balance);
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("health")]
    public IActionResult Health() => Ok(new { status = "Healthy", timestamp = DateTime.UtcNow });
}
