using System.Text;
using System.Text.Json;
using Confluent.Kafka;
using EBankingSerializationAPI.Models;

namespace EBankingSerializationAPI.Serializers;

/// <summary>
/// Typed JSON serializer for Transaction objects.
/// Validates the transaction before serializing to catch errors early
/// (before sending to Kafka), rather than failing at the consumer side.
/// </summary>
public class TransactionJsonSerializer : ISerializer<Transaction>
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public byte[] Serialize(Transaction data, SerializationContext context)
    {
        ArgumentNullException.ThrowIfNull(data);

        // Validate BEFORE serializing — reject invalid data at the producer
        Validate(data);

        var bytes = JsonSerializer.SerializeToUtf8Bytes(data, data.GetType(), JsonOptions);

        Console.WriteLine($"[SERIALIZER] ✅ Transaction {data.TransactionId} serialized ({bytes.Length} bytes)");
        return bytes;
    }

    private static void Validate(Transaction tx)
    {
        if (string.IsNullOrWhiteSpace(tx.TransactionId))
            throw new ArgumentException("TransactionId is required");

        if (string.IsNullOrWhiteSpace(tx.CustomerId))
            throw new ArgumentException("CustomerId is required");

        if (tx.Amount <= 0)
            throw new ArgumentException($"Amount must be > 0 (got {tx.Amount})");

        if (string.IsNullOrWhiteSpace(tx.Currency) || tx.Currency.Length != 3)
            throw new ArgumentException($"Currency must be a 3-letter ISO code (got '{tx.Currency}')");

        if (string.IsNullOrWhiteSpace(tx.FromAccount))
            throw new ArgumentException("FromAccount is required");

        if (string.IsNullOrWhiteSpace(tx.ToAccount))
            throw new ArgumentException("ToAccount is required");
    }
}
