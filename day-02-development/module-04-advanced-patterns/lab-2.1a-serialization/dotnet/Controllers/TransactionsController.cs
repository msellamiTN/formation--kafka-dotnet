using Microsoft.AspNetCore.Mvc;
using EBankingSerializationAPI.Models;
using EBankingSerializationAPI.Services;

namespace EBankingSerializationAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class TransactionsController : ControllerBase
{
    private readonly SerializationProducerService _producer;
    private readonly SchemaEvolutionConsumerService _consumer;
    private readonly ILogger<TransactionsController> _logger;

    public TransactionsController(
        SerializationProducerService producer,
        SchemaEvolutionConsumerService consumer,
        ILogger<TransactionsController> logger)
    {
        _producer = producer;
        _consumer = consumer;
        _logger = logger;
    }

    /// <summary>
    /// Send a v1 transaction using the typed ISerializer&lt;Transaction&gt; with validation.
    /// Invalid transactions (amount &lt;= 0, missing fields) are rejected BEFORE reaching Kafka.
    /// </summary>
    [HttpPost]
    public async Task<IActionResult> SendTransactionV1([FromBody] Transaction tx)
    {
        if (string.IsNullOrWhiteSpace(tx.TransactionId))
            tx.TransactionId = $"TX-{Guid.NewGuid().ToString()[..8]}";

        tx.Timestamp = DateTime.UtcNow;

        var result = await _producer.SendTransactionV1Async(tx);

        return result.Status switch
        {
            "Produced" => Ok(result),
            "RejectedByValidation" => BadRequest(result),
            _ => StatusCode(500, result)
        };
    }

    /// <summary>
    /// Send a v2 transaction (with riskScore and sourceChannel fields).
    /// Demonstrates schema evolution — the background consumer (v1 deserializer)
    /// will read this message and ignore the extra fields (BACKWARD compatibility).
    /// </summary>
    [HttpPost("v2")]
    public async Task<IActionResult> SendTransactionV2([FromBody] TransactionV2 tx)
    {
        if (string.IsNullOrWhiteSpace(tx.TransactionId))
            tx.TransactionId = $"TX-V2-{Guid.NewGuid().ToString()[..8]}";

        tx.Timestamp = DateTime.UtcNow;

        var result = await _producer.SendTransactionV2Async(tx);

        return result.Status switch
        {
            "Produced" => Ok(result),
            "RejectedByValidation" => BadRequest(result),
            _ => StatusCode(500, result)
        };
    }

    /// <summary>
    /// Show schema version info and how the typed serializer/deserializer works.
    /// </summary>
    [HttpGet("schema-info")]
    public IActionResult GetSchemaInfo()
    {
        return Ok(new
        {
            schemas = new[]
            {
                new
                {
                    version = 1,
                    type = "Transaction",
                    fields = new[] { "transactionId", "customerId", "fromAccount", "toAccount", "amount", "currency", "type", "description", "timestamp" },
                    serializer = "TransactionJsonSerializer (ISerializer<Transaction>)",
                    deserializer = "TransactionJsonDeserializer (IDeserializer<Transaction>)",
                    validation = "amount > 0, currency 3-letter ISO, required: transactionId, customerId, fromAccount, toAccount"
                },
                new
                {
                    version = 2,
                    type = "TransactionV2 (extends Transaction)",
                    fields = new[] { "transactionId", "customerId", "fromAccount", "toAccount", "amount", "currency", "type", "description", "timestamp", "riskScore (NEW)", "sourceChannel (NEW)" },
                    serializer = "JsonSerializer (raw, v2 fields included)",
                    deserializer = "TransactionV2JsonDeserializer (IDeserializer<TransactionV2>)",
                    validation = "same as v1 + riskScore must be 0.0-1.0 if present"
                }
            },
            compatibility = new
            {
                backward = "v1 consumer can read v2 messages (extra fields ignored) ✅",
                forward = "v2 consumer can read v1 messages (riskScore = null) ✅",
                full = "Both directions supported ✅"
            },
            kafkaHeaders = new
            {
                schemaVersion = "header 'schema-version' added to each message (1 or 2)",
                serializer = "header 'serializer' identifies the serializer used",
                source = "header 'source' identifies the producing application"
            }
        });
    }

    /// <summary>
    /// List recently consumed messages with schema version and compatibility info.
    /// The background consumer uses a v1 deserializer to demonstrate BACKWARD compatibility.
    /// </summary>
    [HttpGet("consumed")]
    public IActionResult GetConsumedMessages()
    {
        var messages = _consumer.GetConsumedMessages();
        var metrics = _consumer.GetMetrics();

        return Ok(new
        {
            consumerStatus = metrics.Status,
            deserializerUsed = "TransactionJsonDeserializer (v1)",
            totalConsumed = metrics.TotalConsumed,
            v1Messages = metrics.V1Messages,
            v2MessagesReadByV1Deserializer = metrics.V2Messages,
            deserializationErrors = metrics.DeserializationErrors,
            recentMessages = messages
        });
    }

    /// <summary>
    /// Serialization and schema evolution metrics.
    /// </summary>
    [HttpGet("metrics")]
    public IActionResult GetMetrics()
    {
        var producerMetrics = _producer.GetMetrics();
        var consumerMetrics = _consumer.GetMetrics();

        return Ok(new
        {
            producer = producerMetrics,
            consumer = consumerMetrics
        });
    }
}
