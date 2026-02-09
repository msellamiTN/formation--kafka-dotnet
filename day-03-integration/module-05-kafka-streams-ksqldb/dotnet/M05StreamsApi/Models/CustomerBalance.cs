namespace M05StreamsApi.Models;

public sealed class CustomerBalance
{
    public string CustomerId { get; set; } = string.Empty;
    public decimal Balance { get; set; }
    public long TransactionCount { get; set; }
    public DateTime LastUpdated { get; set; }
    public string LastTransactionId { get; set; } = string.Empty;
}
