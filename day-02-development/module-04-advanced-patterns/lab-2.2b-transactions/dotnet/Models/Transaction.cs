using System.Text.Json.Serialization;

namespace EBankingTransactionsAPI.Models;

public class Transaction
{
    [JsonPropertyName("transactionId")]
    public string TransactionId { get; set; } = string.Empty;

    [JsonPropertyName("customerId")]
    public string CustomerId { get; set; } = string.Empty;

    [JsonPropertyName("fromAccount")]
    public string FromAccount { get; set; } = string.Empty;

    [JsonPropertyName("toAccount")]
    public string ToAccount { get; set; } = string.Empty;

    [JsonPropertyName("amount")]
    public decimal Amount { get; set; }

    [JsonPropertyName("currency")]
    public string Currency { get; set; } = "EUR";

    [JsonPropertyName("type")]
    public int Type { get; set; }

    [JsonPropertyName("description")]
    public string? Description { get; set; }

    [JsonPropertyName("timestamp")]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}

public class TransactionRequest
{
    [JsonPropertyName("transactions")]
    public List<Transaction> Transactions { get; set; } = new();
}

public class TransactionResult
{
    public string TransactionId { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string TransactionalId { get; set; } = string.Empty;
    public int Partition { get; set; }
    public long Offset { get; set; }
    public DateTime Timestamp { get; set; }
    public string? ErrorMessage { get; set; }
}

public class TransactionalMetrics
{
    public string TransactionalId { get; set; } = string.Empty;
    public long TransactionsProduced { get; set; }
    public long TransactionsCommitted { get; set; }
    public long TransactionsAborted { get; set; }
    public long ActiveTransactions { get; set; }
    public string ProducerState { get; set; } = string.Empty;
    public DateTime LastTransactionAt { get; set; }
}
