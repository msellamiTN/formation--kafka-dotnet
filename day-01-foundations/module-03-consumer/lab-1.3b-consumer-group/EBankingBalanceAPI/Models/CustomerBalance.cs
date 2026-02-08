namespace EBankingBalanceAPI.Models;

public class CustomerBalance
{
    public string CustomerId { get; set; } = string.Empty;
    public decimal Balance { get; set; }
    public int TransactionCount { get; set; }
    public DateTime LastUpdated { get; set; }
    public string LastTransactionId { get; set; } = string.Empty;
}

public class RebalancingEvent
{
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public string EventType { get; set; } = string.Empty; // Assigned, Revoked, Lost
    public List<int> Partitions { get; set; } = new();
    public string Details { get; set; } = string.Empty;
}

public class ConsumerGroupMetrics
{
    public string ConsumerId { get; set; } = string.Empty;
    public string GroupId { get; set; } = string.Empty;
    public string Status { get; set; } = "Unknown";
    public List<int> AssignedPartitions { get; set; } = new();
    public long MessagesConsumed { get; set; }
    public long BalanceUpdates { get; set; }
    public long ProcessingErrors { get; set; }
    public Dictionary<int, long> PartitionOffsets { get; set; } = new();
    public List<RebalancingEvent> RebalancingHistory { get; set; } = new();
    public DateTime StartedAt { get; set; }
    public DateTime LastMessageAt { get; set; }
}
