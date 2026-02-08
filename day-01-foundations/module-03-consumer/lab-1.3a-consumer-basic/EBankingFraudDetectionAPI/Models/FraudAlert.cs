namespace EBankingFraudDetectionAPI.Models;

public class FraudAlert
{
    public string TransactionId { get; set; } = string.Empty;
    public string CustomerId { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "EUR";
    public string Type { get; set; } = string.Empty;
    public int RiskScore { get; set; }
    public string RiskLevel { get; set; } = "Low"; // Low, Medium, High, Critical
    public string Reason { get; set; } = string.Empty;
    public DateTime DetectedAt { get; set; } = DateTime.UtcNow;

    // Kafka Metadata
    public int KafkaPartition { get; set; }
    public long KafkaOffset { get; set; }
}

public class ConsumerMetrics
{
    public long MessagesConsumed { get; set; }
    public long FraudAlertsGenerated { get; set; }
    public long ProcessingErrors { get; set; }
    public double AverageRiskScore { get; set; }
    public string ConsumerGroupId { get; set; } = string.Empty;
    public string ConsumerStatus { get; set; } = "Unknown";
    public Dictionary<int, long> PartitionOffsets { get; set; } = new();
    public DateTime StartedAt { get; set; }
    public DateTime LastMessageAt { get; set; }
}
