using Microsoft.AspNetCore.Mvc;
using M05StreamsApi.Services;

namespace M05StreamsApi.Controllers;

[ApiController]
[Route("api/v1")]
public sealed class StoresController : ControllerBase
{
    private readonly StreamsState _state;

    public StoresController(StreamsState state)
    {
        _state = state;
    }

    [HttpGet("stores/{storeName}/all")]
    public IActionResult GetAll(string storeName)
    {
        if (string.Equals(storeName, StreamsState.SalesByProductStore, StringComparison.Ordinal))
        {
            return Ok(_state.SalesByProduct);
        }

        if (string.Equals(storeName, StreamsState.ProductsStore, StringComparison.Ordinal))
        {
            return Ok(_state.Products);
        }

        return NotFound(new { error = "Store not found" });
    }

    [HttpGet("stores/{storeName}/{key}")]
    public IActionResult GetByKey(string storeName, string key)
    {
        if (string.Equals(storeName, StreamsState.SalesByProductStore, StringComparison.Ordinal))
        {
            return _state.SalesByProduct.TryGetValue(key, out var agg) ? Ok(agg) : NotFound();
        }

        if (string.Equals(storeName, StreamsState.ProductsStore, StringComparison.Ordinal))
        {
            return _state.Products.TryGetValue(key, out var product) ? Ok(product) : NotFound();
        }

        return NotFound(new { error = "Store not found" });
    }
}
