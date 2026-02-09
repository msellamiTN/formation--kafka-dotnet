using System.Text.Json;
using Confluent.Kafka;
using EBankingSerializationAPI.Models;

namespace EBankingSerializationAPI.Serializers;

/// <summary>
/// Typed JSON deserializer for Transaction objects.
/// Uses lenient options to support BACKWARD/FORWARD schema evolution:
/// - Unknown properties are ignored (BACKWARD: v1 consumer reads v2 message)
/// - Missing optional properties get default values (FORWARD: v2 consumer reads v1 message)
/// </summary>
public class TransactionJsonDeserializer : IDeserializer<Transaction>
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        // Allow unknown properties for BACKWARD compatibility
        // (v1 consumer can read v2 messages with extra fields)
    };

    public Transaction Deserialize(ReadOnlySpan<byte> data, bool isNull, SerializationContext context)
    {
        if (isNull || data.IsEmpty)
            throw new InvalidOperationException("Cannot deserialize null or empty message");

        try
        {
            var transaction = JsonSerializer.Deserialize<Transaction>(data, JsonOptions)
                ?? throw new InvalidOperationException("Deserialization returned null");

            Console.WriteLine(
                $"[DESERIALIZER] ✅ Transaction {transaction.TransactionId}: " +
                $"Amount={transaction.Amount} {transaction.Currency}, " +
                $"Customer={transaction.CustomerId}");

            return transaction;
        }
        catch (JsonException ex)
        {
            Console.WriteLine($"[DESERIALIZER] ❌ Failed to deserialize: {ex.Message}");
            throw new InvalidOperationException($"JSON deserialization failed: {ex.Message}", ex);
        }
    }
}

/// <summary>
/// V2 deserializer that reads TransactionV2 (with riskScore).
/// Demonstrates FORWARD compatibility: can read v1 messages (riskScore will be null).
/// </summary>
public class TransactionV2JsonDeserializer : IDeserializer<TransactionV2>
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    public TransactionV2 Deserialize(ReadOnlySpan<byte> data, bool isNull, SerializationContext context)
    {
        if (isNull || data.IsEmpty)
            throw new InvalidOperationException("Cannot deserialize null or empty message");

        var transaction = JsonSerializer.Deserialize<TransactionV2>(data, JsonOptions)
            ?? throw new InvalidOperationException("Deserialization returned null");

        Console.WriteLine(
            $"[DESERIALIZER-V2] ✅ Transaction {transaction.TransactionId}: " +
            $"Amount={transaction.Amount} {transaction.Currency}, " +
            $"RiskScore={transaction.RiskScore?.ToString("F2") ?? "null (v1 message)"}");

        return transaction;
    }
}
