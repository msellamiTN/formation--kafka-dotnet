using System.Collections.Concurrent;
using M05StreamsApi.Models;

namespace M05StreamsApi.Services;

public sealed class StreamsState
{
    public const string SalesByProductStore = "sales-by-product-store";
    public const string ProductsStore = "products-store";

    private readonly ConcurrentDictionary<string, SaleAggregate> _salesByProduct = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, Product> _products = new(StringComparer.Ordinal);

    public IReadOnlyDictionary<string, SaleAggregate> SalesByProduct => _salesByProduct;
    public IReadOnlyDictionary<string, Product> Products => _products;

    public SaleAggregate GetOrCreateAggregate(string productId)
    {
        return _salesByProduct.GetOrAdd(productId, _ => new SaleAggregate());
    }

    public void UpsertProduct(Product product)
    {
        if (string.IsNullOrWhiteSpace(product.Id))
        {
            return;
        }

        _products[product.Id] = product;
    }

    public Product? TryGetProduct(string productId)
    {
        return _products.TryGetValue(productId, out var product) ? product : null;
    }
}
