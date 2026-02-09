using System.Text.Json.Serialization;

namespace EBankingSerializationAPI.Models;

/// <summary>
/// Transaction model v1 - Base banking transaction
/// </summary>
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

/// <summary>
/// Transaction model v2 - Adds riskScore for fraud detection integration
/// Demonstrates BACKWARD-compatible schema evolution (new optional field)
/// </summary>
public class TransactionV2 : Transaction
{
    [JsonPropertyName("riskScore")]
    public double? RiskScore { get; set; }

    [JsonPropertyName("sourceChannel")]
    public string? SourceChannel { get; set; }
}
