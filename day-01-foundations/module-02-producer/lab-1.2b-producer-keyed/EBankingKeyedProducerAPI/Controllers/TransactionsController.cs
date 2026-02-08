using Microsoft.AspNetCore.Mvc;
using EBankingKeyedProducerAPI.Models;
using EBankingKeyedProducerAPI.Services;

namespace EBankingKeyedProducerAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class TransactionsController : ControllerBase
{
    private readonly KeyedKafkaProducerService _kafka;
    private readonly ILogger<TransactionsController> _logger;

    public TransactionsController(KeyedKafkaProducerService kafka, ILogger<TransactionsController> logger)
    {
        _kafka = kafka;
        _logger = logger;
    }

    [HttpPost]
    public async Task<ActionResult<KeyedTransactionResponse>> CreateTransaction(
        [FromBody] Transaction transaction, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(transaction.TransactionId))
            transaction.TransactionId = Guid.NewGuid().ToString();

        var result = await _kafka.SendTransactionAsync(transaction, ct);

        return CreatedAtAction(nameof(GetTransaction),
            new { transactionId = transaction.TransactionId },
            new KeyedTransactionResponse
            {
                TransactionId = transaction.TransactionId,
                CustomerId = transaction.CustomerId,
                KafkaPartition = result.Partition.Value,
                KafkaOffset = result.Offset.Value,
                Timestamp = result.Timestamp.UtcDateTime,
                Status = "Processing"
            });
    }

    [HttpPost("batch")]
    public async Task<ActionResult<BatchKeyedResponse>> CreateBatch(
        [FromBody] List<Transaction> transactions, CancellationToken ct)
    {
        var results = new List<KeyedTransactionResponse>();

        foreach (var tx in transactions)
        {
            if (string.IsNullOrEmpty(tx.TransactionId))
                tx.TransactionId = Guid.NewGuid().ToString();

            var dr = await _kafka.SendTransactionAsync(tx, ct);
            results.Add(new KeyedTransactionResponse
            {
                TransactionId = tx.TransactionId,
                CustomerId = tx.CustomerId,
                KafkaPartition = dr.Partition.Value,
                KafkaOffset = dr.Offset.Value,
                Timestamp = dr.Timestamp.UtcDateTime,
                Status = "Processing"
            });
        }

        return Created("", new BatchKeyedResponse
        {
            ProcessedCount = results.Count,
            Transactions = results
        });
    }

    [HttpGet("stats/partitions")]
    public ActionResult<PartitionStatsResponse> GetPartitionStats()
    {
        return Ok(new PartitionStatsResponse
        {
            PartitionDistribution = _kafka.GetPartitionStats(),
            CustomerPartitionMap = _kafka.GetCustomerPartitionMap(),
            TotalMessages = _kafka.GetPartitionStats().Values.Sum()
        });
    }

    [HttpGet("{transactionId}")]
    public ActionResult<KeyedTransactionResponse> GetTransaction(string transactionId)
    {
        return Ok(new KeyedTransactionResponse
        {
            TransactionId = transactionId,
            Status = "Processing",
            Timestamp = DateTime.UtcNow
        });
    }

    [HttpGet("health")]
    public ActionResult GetHealth()
    {
        return Ok(new
        {
            Status = "Healthy",
            Service = "EBanking Keyed Producer API",
            Timestamp = DateTime.UtcNow
        });
    }
}

public class KeyedTransactionResponse
{
    public string TransactionId { get; set; } = string.Empty;
    public string CustomerId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public int KafkaPartition { get; set; }
    public long KafkaOffset { get; set; }
    public DateTime Timestamp { get; set; }
}

public class BatchKeyedResponse
{
    public int ProcessedCount { get; set; }
    public List<KeyedTransactionResponse> Transactions { get; set; } = new();
}

public class PartitionStatsResponse
{
    public Dictionary<int, int> PartitionDistribution { get; set; } = new();
    public Dictionary<string, int> CustomerPartitionMap { get; set; } = new();
    public int TotalMessages { get; set; }
}
