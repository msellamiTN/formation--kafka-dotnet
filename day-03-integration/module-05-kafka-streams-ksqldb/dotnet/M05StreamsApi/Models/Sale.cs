namespace M05StreamsApi.Models;

public sealed class Sale
{
    public string ProductId { get; set; } = string.Empty;
    public int Quantity { get; set; }
    public decimal UnitPrice { get; set; }
    public long Timestamp { get; set; } = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

    public decimal TotalAmount => Quantity * UnitPrice;
}
