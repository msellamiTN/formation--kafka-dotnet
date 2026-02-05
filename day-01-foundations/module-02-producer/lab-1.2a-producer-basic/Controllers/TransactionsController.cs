using Microsoft.AspNetCore.Mvc;
using EBankingProducerAPI.Models;
using EBankingProducerAPI.Services;

namespace EBankingProducerAPI.Controllers
{
    /// <summary>
    /// API Controller for managing banking transactions
    /// </summary>
    [ApiController]
    [Route("api/[controller]")]
    [Produces("application/json")]
    public class TransactionsController : ControllerBase
    {
        private readonly KafkaProducerService _kafkaProducer;
        private readonly ILogger<TransactionsController> _logger;

        public TransactionsController(
            KafkaProducerService kafkaProducer,
            ILogger<TransactionsController> logger)
        {
            _kafkaProducer = kafkaProducer;
            _logger = logger;
        }

        /// <summary>
        /// Create a new banking transaction
        /// </summary>
        /// <param name="transaction">Transaction details</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Created transaction with Kafka metadata</returns>
        [HttpPost]
        [ProducesResponseType(typeof(TransactionResponse), StatusCodes.Status201Created)]
        [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<TransactionResponse>> CreateTransaction(
            [FromBody] Transaction transaction,
            CancellationToken cancellationToken = default)
        {
            try
            {
                // Validate transaction
                if (!ModelState.IsValid)
                {
                    _logger.LogWarning("Invalid transaction model: {ModelState}", ModelState);
                    return BadRequest(new ErrorResponse
                    {
                        ErrorCode = "VALIDATION_ERROR",
                        Message = "Invalid transaction data",
                        Details = ModelState.Values
                            .SelectMany(v => v.Errors)
                            .Select(e => e.ErrorMessage)
                            .ToList()
                    });
                }

                // Set transaction ID if not provided
                if (string.IsNullOrEmpty(transaction.TransactionId))
                {
                    transaction.TransactionId = Guid.NewGuid().ToString();
                }

                // Send to Kafka
                var deliveryResult = await _kafkaProducer.SendTransactionAsync(transaction, cancellationToken);

                // Return response
                var response = new TransactionResponse
                {
                    TransactionId = transaction.TransactionId,
                    Status = TransactionStatus.Processing,
                    KafkaPartition = deliveryResult.Partition.Value,
                    KafkaOffset = deliveryResult.Offset.Value,
                    Timestamp = deliveryResult.Timestamp.UtcDateTime,
                    Message = "Transaction created and sent to Kafka successfully"
                };

                _logger.LogInformation(
                    "Transaction {TransactionId} created and sent to partition {Partition} at offset {Offset}",
                    transaction.TransactionId,
                    deliveryResult.Partition.Value,
                    deliveryResult.Offset.Value);

                return CreatedAtAction(
                    nameof(GetTransaction),
                    new { transactionId = transaction.TransactionId },
                    response);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating transaction");
                return StatusCode(StatusCodes.Status500InternalServerError, new ErrorResponse
                {
                    ErrorCode = "INTERNAL_ERROR",
                    Message = "An error occurred while processing the transaction",
                    Details = new List<string> { ex.Message }
                });
            }
        }

        /// <summary>
        /// Create multiple transactions in batch
        /// </summary>
        /// <param name="transactions">List of transactions</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Batch processing results</returns>
        [HttpPost("batch")]
        [ProducesResponseType(typeof(BatchTransactionResponse), StatusCodes.Status201Created)]
        [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
        [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status500InternalServerError)]
        public async Task<ActionResult<BatchTransactionResponse>> CreateTransactionsBatch(
            [FromBody] List<Transaction> transactions,
            CancellationToken cancellationToken = default)
        {
            try
            {
                if (transactions == null || !transactions.Any())
                {
                    return BadRequest(new ErrorResponse
                    {
                        ErrorCode = "VALIDATION_ERROR",
                        Message = "Transaction list cannot be empty",
                        Details = new List<string>()
                    });
                }

                // Validate all transactions
                var validationErrors = new List<string>();
                foreach (var transaction in transactions)
                {
                    if (!TryValidateModel(transaction))
                    {
                        validationErrors.AddRange(ModelState.Values
                            .SelectMany(v => v.Errors)
                            .Select(e => e.ErrorMessage));
                    }
                }

                if (validationErrors.Any())
                {
                    return BadRequest(new ErrorResponse
                    {
                        ErrorCode = "VALIDATION_ERROR",
                        Message = "Invalid transaction data in batch",
                        Details = validationErrors
                    });
                }

                // Set transaction IDs if not provided
                foreach (var transaction in transactions)
                {
                    if (string.IsNullOrEmpty(transaction.TransactionId))
                    {
                        transaction.TransactionId = Guid.NewGuid().ToString();
                    }
                }

                // Send batch to Kafka
                var deliveryResults = await _kafkaProducer.SendTransactionsBatchAsync(transactions, cancellationToken);

                // Create response
                var transactionResponses = deliveryResults.Select((result, index) => new TransactionResponse
                {
                    TransactionId = transactions[index].TransactionId,
                    Status = TransactionStatus.Processing,
                    KafkaPartition = result.Partition.Value,
                    KafkaOffset = result.Offset.Value,
                    Timestamp = result.Timestamp.UtcDateTime,
                    Message = "Transaction sent to Kafka successfully"
                }).ToList();

                var response = new BatchTransactionResponse
                {
                    ProcessedCount = transactionResponses.Count,
                    Transactions = transactionResponses,
                    Message = $"Batch of {transactionResponses.Count} transactions processed successfully"
                };

                _logger.LogInformation(
                    "Batch of {Count} transactions sent to Kafka successfully",
                    transactionResponses.Count);

                return Created("", response);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating transaction batch");
                return StatusCode(StatusCodes.Status500InternalServerError, new ErrorResponse
                {
                    ErrorCode = "INTERNAL_ERROR",
                    Message = "An error occurred while processing the transaction batch",
                    Details = new List<string> { ex.Message }
                });
            }
        }

        /// <summary>
        /// Get transaction status (placeholder for future implementation)
        /// </summary>
        /// <param name="transactionId">Transaction identifier</param>
        /// <returns>Transaction status</returns>
        [HttpGet("{transactionId}")]
        [ProducesResponseType(typeof(TransactionStatusResponse), StatusCodes.Status200OK)]
        [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
        public ActionResult<TransactionStatusResponse> GetTransaction(string transactionId)
        {
            // This is a placeholder implementation
            // In a real scenario, you would query a database or cache for transaction status
            return Ok(new TransactionStatusResponse
            {
                TransactionId = transactionId,
                Status = TransactionStatus.Processing,
                Message = "Transaction is being processed",
                LastUpdated = DateTime.UtcNow
            });
        }

        /// <summary>
        /// Health check endpoint
        /// </summary>
        /// <returns>Service health status</returns>
        [HttpGet("health")]
        [ProducesResponseType(typeof(HealthResponse), StatusCodes.Status200OK)]
        public ActionResult<HealthResponse> GetHealth()
        {
            return Ok(new HealthResponse
            {
                Status = "Healthy",
                Timestamp = DateTime.UtcNow,
                Version = "1.0.0",
                Service = "EBanking Producer API"
            });
        }
    }

    // Response DTOs
    public class TransactionResponse
    {
        public string TransactionId { get; set; } = string.Empty;
        public TransactionStatus Status { get; set; }
        public int KafkaPartition { get; set; }
        public long KafkaOffset { get; set; }
        public DateTime Timestamp { get; set; }
        public string Message { get; set; } = string.Empty;
    }

    public class BatchTransactionResponse
    {
        public int ProcessedCount { get; set; }
        public List<TransactionResponse> Transactions { get; set; } = new();
        public string Message { get; set; } = string.Empty;
    }

    public class TransactionStatusResponse
    {
        public string TransactionId { get; set; } = string.Empty;
        public TransactionStatus Status { get; set; }
        public string Message { get; set; } = string.Empty;
        public DateTime LastUpdated { get; set; }
    }

    public class ErrorResponse
    {
        public string ErrorCode { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public List<string> Details { get; set; } = new();
    }

    public class HealthResponse
    {
        public string Status { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public string Version { get; set; } = string.Empty;
        public string Service { get; set; } = string.Empty;
    }
}
