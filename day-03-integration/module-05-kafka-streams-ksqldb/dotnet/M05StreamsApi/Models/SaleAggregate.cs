namespace M05StreamsApi.Models;

public sealed class SaleAggregate
{
    public long Count { get; set; }
    public decimal TotalAmount { get; set; }
    public long TotalQuantity { get; set; }

    public void Add(Sale sale)
    {
        Count++;
        TotalAmount += sale.TotalAmount;
        TotalQuantity += sale.Quantity;
    }
}
