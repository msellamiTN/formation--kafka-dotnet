using System.Text.Json.Serialization;

namespace EBankingIdempotentProducerAPI.Models;

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

public class BatchRequest
{
    [JsonPropertyName("count")]
    public int Count { get; set; } = 10;

    [JsonPropertyName("customerId")]
    public string CustomerId { get; set; } = "CUST-BATCH-001";
}
