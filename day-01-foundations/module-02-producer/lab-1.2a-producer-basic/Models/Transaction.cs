using System.ComponentModel.DataAnnotations;

namespace EBankingProducerAPI.Models
{
    /// <summary>
    /// Represents a banking transaction for Kafka messaging
    /// </summary>
    public class Transaction
    {
        /// <summary>
        /// Unique transaction identifier
        /// </summary>
        [Required]
        public string TransactionId { get; set; } = string.Empty;

        /// <summary>
        /// Source account number
        /// </summary>
        [Required]
        [StringLength(20, MinimumLength = 10)]
        public string FromAccount { get; set; } = string.Empty;

        /// <summary>
        /// Destination account number
        /// </summary>
        [Required]
        [StringLength(20, MinimumLength = 10)]
        public string ToAccount { get; set; } = string.Empty;

        /// <summary>
        /// Transaction amount
        /// </summary>
        [Required]
        [Range(0.01, 1000000.00)]
        public decimal Amount { get; set; }

        /// <summary>
        /// Currency code (ISO 4217)
        /// </summary>
        [Required]
        [StringLength(3, MinimumLength = 3)]
        public string Currency { get; set; } = "USD";

        /// <summary>
        /// Transaction type
        /// </summary>
        [Required]
        public TransactionType Type { get; set; }

        /// <summary>
        /// Transaction description
        /// </summary>
        [StringLength(500)]
        public string? Description { get; set; }

        /// <summary>
        /// Customer ID who initiated the transaction
        /// </summary>
        [Required]
        public string CustomerId { get; set; } = string.Empty;

        /// <summary>
        /// Transaction timestamp (UTC)
        /// </summary>
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;

        /// <summary>
        /// Geographic location of transaction
        /// </summary>
        public Location? Location { get; set; }

        /// <summary>
        /// Risk assessment score
        /// </summary>
        [Range(0, 100)]
        public int RiskScore { get; set; } = 0;

        /// <summary>
        /// Transaction status
        /// </summary>
        public TransactionStatus Status { get; set; } = TransactionStatus.Pending;
    }

    /// <summary>
    /// Transaction types supported by the banking system
    /// </summary>
    public enum TransactionType
    {
        Transfer = 1,
        Payment = 2,
        Deposit = 3,
        Withdrawal = 4,
        CardPayment = 5,
        InternationalTransfer = 6,
        BillPayment = 7
    }

    /// <summary>
    /// Transaction status values
    /// </summary>
    public enum TransactionStatus
    {
        Pending = 1,
        Processing = 2,
        Completed = 3,
        Failed = 4,
        Rejected = 5,
        UnderReview = 6
    }

    /// <summary>
    /// Geographic location information
    /// </summary>
    public class Location
    {
        public string Country { get; set; } = string.Empty;
        public string City { get; set; } = string.Empty;
        public string IpAddress { get; set; } = string.Empty;
        public decimal Latitude { get; set; }
        public decimal Longitude { get; set; }
    }
}
