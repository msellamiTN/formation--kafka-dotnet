namespace EBankingAuditAPI.Models;

public class AuditRecord
{
    public string AuditId { get; set; } = Guid.NewGuid().ToString();
    public string TransactionId { get; set; } = string.Empty;
    public string CustomerId { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "EUR";
    public int Type { get; set; }
    public string FromAccount { get; set; } = string.Empty;
    public string ToAccount { get; set; } = string.Empty;
    public DateTime TransactionTimestamp { get; set; }
    public DateTime AuditTimestamp { get; set; } = DateTime.UtcNow;
    public string Status { get; set; } = "Recorded"; // Recorded, Failed, DLQ

    // Kafka Metadata
    public int KafkaPartition { get; set; }
    public long KafkaOffset { get; set; }
    public string ConsumerGroupId { get; set; } = string.Empty;

    // Traceability
    public int ProcessingAttempts { get; set; } = 1;
    public string? ErrorDetails { get; set; }
}

public class DlqMessage
{
    public string TransactionId { get; set; } = string.Empty;
    public string OriginalMessage { get; set; } = string.Empty;
    public string ErrorReason { get; set; } = string.Empty;
    public int Attempts { get; set; }
    public DateTime FailedAt { get; set; } = DateTime.UtcNow;
    public int OriginalPartition { get; set; }
    public long OriginalOffset { get; set; }
}

public class AuditMetrics
{
    public long MessagesConsumed { get; set; }
    public long AuditRecordsCreated { get; set; }
    public long DuplicatesSkipped { get; set; }
    public long ProcessingErrors { get; set; }
    public long MessagesSentToDlq { get; set; }
    public long ManualCommits { get; set; }
    public string ConsumerStatus { get; set; } = "Unknown";
    public string GroupId { get; set; } = string.Empty;
    public Dictionary<int, long> CommittedOffsets { get; set; } = new();
    public DateTime StartedAt { get; set; }
    public DateTime LastCommitAt { get; set; }
    public DateTime LastMessageAt { get; set; }
}
