using Confluent.Kafka;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using EBankingProducerAPI.Models;

namespace EBankingProducerAPI.Services
{
    /// <summary>
    /// Kafka Producer service for sending banking transactions
    /// </summary>
    public class KafkaProducerService : IDisposable
    {
        private readonly IProducer<string, string> _producer;
        private readonly ILogger<KafkaProducerService> _logger;
        private readonly string _topic;

        public KafkaProducerService(IConfiguration configuration, ILogger<KafkaProducerService> logger)
        {
            _logger = logger;
            _topic = configuration["Kafka:Topic"] ?? "banking.transactions";

            var producerConfig = new ProducerConfig
            {
                BootstrapServers = configuration["Kafka:BootstrapServers"] ?? "localhost:9092",
                ClientId = configuration["Kafka:ClientId"] ?? "ebanking-producer-api",
                Acks = Acks.All,
                EnableIdempotence = true,
                MessageSendMaxRetries = 3,
                RetryBackoffMs = 1000,
                BatchSize = 16384,
                LingerMs = 10,
                CompressionType = CompressionType.Snappy,
                SecurityProtocol = SecurityProtocol.Plaintext
            };

            _producer = new ProducerBuilder<string, string>(producerConfig)
                .SetErrorHandler((_, error) =>
                {
                    _logger.LogError("Kafka Producer Error: {ErrorReason} (Code: {ErrorCode})", 
                        error.Reason, error.Code);
                })
                .SetLogHandler((_, message) =>
                {
                    if (message.Level >= SyslogLevel.Warning)
                    {
                        _logger.LogWarning("Kafka Producer Log: {Message}", message.Message);
                    }
                })
                .Build();
        }

        /// <summary>
        /// Send a banking transaction to Kafka
        /// </summary>
        /// <param name="transaction">The transaction to send</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Delivery result with metadata</returns>
        public async Task<DeliveryResult<string, string>> SendTransactionAsync(
            Transaction transaction, 
            CancellationToken cancellationToken = default)
        {
            try
            {
                // Generate correlation ID if not present
                var correlationId = Guid.NewGuid().ToString();
                
                // Serialize transaction to JSON
                var transactionJson = JsonSerializer.Serialize(transaction, new JsonSerializerOptions
                {
                    WriteIndented = false,
                    PropertyNamingPolicy = JsonNamingPolicy.CamelCase
                });

                // Create message with headers
                var message = new Message<string, string>
                {
                    Key = transaction.TransactionId,
                    Value = transactionJson,
                    Headers = new Headers
                    {
                        { "correlation-id", System.Text.Encoding.UTF8.GetBytes(correlationId) },
                        { "event-type", System.Text.Encoding.UTF8.GetBytes("transaction.created") },
                        { "event-version", System.Text.Encoding.UTF8.GetBytes("1.0") },
                        { "source", System.Text.Encoding.UTF8.GetBytes("ebanking-api") },
                        { "customer-id", System.Text.Encoding.UTF8.GetBytes(transaction.CustomerId) },
                        { "transaction-type", System.Text.Encoding.UTF8.GetBytes(transaction.Type.ToString()) },
                        { "risk-score", System.Text.Encoding.UTF8.GetBytes(transaction.RiskScore.ToString()) }
                    },
                    Timestamp = new Timestamp(transaction.Timestamp)
                };

                // Send message
                var deliveryResult = await _producer.ProduceAsync(_topic, message, cancellationToken);
                
                _logger.LogInformation(
                    "Transaction {TransactionId} sent successfully to partition {Partition} at offset {Offset}",
                    transaction.TransactionId,
                    deliveryResult.Partition.Value,
                    deliveryResult.Offset.Value);

                return deliveryResult;
            }
            catch (ProduceException<string, string> ex)
            {
                _logger.LogError(ex, 
                    "Failed to send transaction {TransactionId}. Error: {Error} (Code: {ErrorCode})", 
                    transaction.TransactionId, ex.Error.Reason, ex.Error.Code);
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error sending transaction {TransactionId}", 
                    transaction.TransactionId);
                throw;
            }
        }

        /// <summary>
        /// Send multiple transactions in batch
        /// </summary>
        /// <param name="transactions">List of transactions to send</param>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>List of delivery results</returns>
        public async Task<List<DeliveryResult<string, string>>> SendTransactionsBatchAsync(
            IEnumerable<Transaction> transactions,
            CancellationToken cancellationToken = default)
        {
            var results = new List<DeliveryResult<string, string>>();
            var tasks = new List<Task<DeliveryResult<string, string>>>();

            foreach (var transaction in transactions)
            {
                tasks.Add(SendTransactionAsync(transaction, cancellationToken));
            }

            try
            {
                var deliveryResults = await Task.WhenAll(tasks);
                results.AddRange(deliveryResults);
                
                _logger.LogInformation("Batch of {Count} transactions sent successfully", 
                    deliveryResults.Length);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error occurred during batch transaction sending");
                throw;
            }

            return results;
        }

        /// <summary>
        /// Flush producer to ensure all messages are sent
        /// </summary>
        /// <param name="cancellationToken">Cancellation token</param>
        /// <returns>Number of messages remaining in queue</returns>
        public async Task<int> FlushAsync(CancellationToken cancellationToken = default)
        {
            _logger.LogInformation("Flushing Kafka producer...");
            var result = _producer.Flush(cancellationToken);
            _logger.LogInformation("Producer flush completed. {Count} messages remaining", result);
            return result;
        }

        public void Dispose()
        {
            _producer?.Dispose();
            _logger.LogInformation("Kafka producer disposed");
        }
    }
}
