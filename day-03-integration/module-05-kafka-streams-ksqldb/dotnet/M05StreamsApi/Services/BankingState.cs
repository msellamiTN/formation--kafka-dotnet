using System.Collections.Concurrent;
using M05StreamsApi.Models;

namespace M05StreamsApi.Services;

public sealed class BankingState
{
    private readonly ConcurrentDictionary<string, CustomerBalance> _balances = new(StringComparer.Ordinal);

    public IReadOnlyDictionary<string, CustomerBalance> Balances => _balances;

    public CustomerBalance GetOrCreate(string customerId)
    {
        return _balances.GetOrAdd(customerId, id => new CustomerBalance
        {
            CustomerId = id,
            LastUpdated = DateTime.UtcNow
        });
    }

    public bool TryGet(string customerId, out CustomerBalance balance)
    {
        return _balances.TryGetValue(customerId, out balance!);
    }
}
