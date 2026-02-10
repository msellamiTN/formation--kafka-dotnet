using ksqlDB.RestApi.Client.KSql.Query.Context;
using ksqlDB.RestApi.Client.KSql.RestApi;
using ksqlDB.RestApi.Client.KSql.RestApi.Statements;
using ksqlDB.RestApi.Client.KSql.RestApi.Http;
using BankingKsqlDBLab.Models;
using System.Reactive.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;

namespace BankingKsqlDBLab.Services;

public class KsqlDbService
{
    private readonly KSqlDbRestApiClient _restApiClient;
    private readonly KSqlDBContext _context;
    private readonly ILogger<KsqlDbService> _logger;
    private readonly string _ksqlDbUrl;

    public KsqlDbService(string ksqlDbUrl, ILogger<KsqlDbService> logger)
    {
        _logger = logger;
        _ksqlDbUrl = ksqlDbUrl;

        var options = new KSqlDBContextOptions(ksqlDbUrl)
        {
            ShouldPluralizeFromItemName = false
        };

        _context = new KSqlDBContext(options);

        var httpClient = new HttpClient { BaseAddress = new Uri(ksqlDbUrl) };
        var httpClientFactory = new HttpClientFactory(httpClient);
        _restApiClient = new KSqlDbRestApiClient(httpClientFactory);
    }

    /// <summary>
    /// Initialize all ksqlDB streams and tables for the lab
    /// </summary>
    public async Task InitializeStreamsAsync()
    {
        _logger.LogInformation("Initializing ksqlDB streams...");

        try
        {
            // Clean up existing streams (reverse dependency order, no DELETE TOPIC)
            await DropStreamIfExistsAsync("fraud_alerts");
            await DropStreamIfExistsAsync("verified_transactions");
            await DropTableIfExistsAsync("hourly_stats");
            await DropTableIfExistsAsync("account_balances");
            await DropStreamIfExistsAsync("transactions");
            await Task.Delay(3000);

            // 1. Create the main transactions stream
            var createTransactions = @"
                CREATE STREAM IF NOT EXISTS transactions (
                    transaction_id VARCHAR,
                    account_id VARCHAR,
                    amount DECIMAL(10,2),
                    transaction_time BIGINT,
                    type VARCHAR,
                    merchant VARCHAR,
                    country VARCHAR,
                    is_online BOOLEAN
                ) WITH (
                    kafka_topic='transactions',
                    value_format='json',
                    timestamp='transaction_time'
                );";

            await ExecuteKsqlStatementAsync(createTransactions);
            _logger.LogInformation("Stream created: transactions");
            await WaitForStreamAsync("TRANSACTIONS");

            // 2. Create the verified transactions stream with fraud detection
            var createVerified = @"
                CREATE STREAM IF NOT EXISTS verified_transactions WITH (
                    kafka_topic='verified_transactions',
                    value_format='json'
                ) AS
                SELECT
                    transaction_id,
                    account_id,
                    amount,
                    type,
                    country,
                    CASE
                        WHEN amount > 10000 THEN 0.8
                        WHEN amount > 5000 AND is_online = false THEN 0.6
                        WHEN merchant LIKE '%CASINO%' THEN 0.7
                        WHEN merchant LIKE '%GAMBLING%' THEN 0.75
                        WHEN is_online = false AND amount > 2000 THEN 0.4
                        ELSE 0.0
                    END AS risk_score,
                    CASE
                        WHEN amount > 10000 THEN true
                        WHEN merchant LIKE '%CASINO%' THEN true
                        WHEN merchant LIKE '%GAMBLING%' THEN true
                        ELSE false
                    END AS is_fraud
                FROM transactions
                WHERE amount > 0
                EMIT CHANGES;";

            await ExecuteKsqlStatementAsync(createVerified);
            _logger.LogInformation("Stream created: verified_transactions");
            await WaitForStreamAsync("VERIFIED_TRANSACTIONS");

            // 3. Create the fraud alerts stream
            var createFraudAlerts = @"
                CREATE STREAM IF NOT EXISTS fraud_alerts WITH (
                    kafka_topic='fraud_alerts',
                    value_format='json'
                ) AS
                SELECT
                    transaction_id,
                    account_id,
                    amount,
                    CASE
                        WHEN amount > 10000 THEN 'Large transaction detected'
                        WHEN merchant LIKE '%CASINO%' THEN 'Casino transaction flagged'
                        WHEN merchant LIKE '%GAMBLING%' THEN 'Gambling merchant flagged'
                        ELSE 'Suspicious activity'
                    END AS reason,
                    risk_score
                FROM verified_transactions
                WHERE is_fraud = true
                EMIT CHANGES;";

            await ExecuteKsqlStatementAsync(createFraudAlerts);
            _logger.LogInformation("Stream created: fraud_alerts");
            await Task.Delay(2000);

            // 4. Create the account balances table (materialized view)
            var createBalances = @"
                CREATE TABLE IF NOT EXISTS account_balances WITH (
                    kafka_topic='account_balances',
                    value_format='json'
                ) AS
                SELECT
                    account_id,
                    SUM(CASE WHEN type='CREDIT' THEN amount ELSE -amount END) AS balance,
                    COUNT(*) AS transaction_count
                FROM transactions
                GROUP BY account_id
                EMIT CHANGES;";

            await ExecuteKsqlStatementAsync(createBalances);
            _logger.LogInformation("Table created: account_balances");
            await Task.Delay(2000);

            // 5. Create hourly stats (windowed aggregation)
            var createHourlyStats = @"
                CREATE TABLE IF NOT EXISTS hourly_stats WITH (
                    kafka_topic='hourly_stats',
                    value_format='json'
                ) AS
                SELECT
                    account_id,
                    WINDOWSTART AS window_start,
                    WINDOWEND AS window_end,
                    SUM(CASE WHEN type='DEBIT' THEN amount ELSE 0 END) AS total_debits,
                    SUM(CASE WHEN type='CREDIT' THEN amount ELSE 0 END) AS total_credits,
                    COUNT(*) AS transaction_count
                FROM transactions
                WINDOW TUMBLING (SIZE 1 HOUR)
                GROUP BY account_id
                EMIT CHANGES;";

            await ExecuteKsqlStatementAsync(createHourlyStats);
            _logger.LogInformation("Table created: hourly_stats (windowed)");

            _logger.LogInformation("Initialization complete!");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during initialization");
            throw;
        }
    }

    public async Task ExecuteKsqlStatementAsync(string ksqlStatement)
    {
        var request = new KSqlDbStatement(ksqlStatement);
        var response = await _restApiClient.ExecuteStatementAsync(request);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync();
            _logger.LogWarning("ksqlDB statement failed: {Status} - {Body}", response.StatusCode, body);
        }
    }

    private async Task DropStreamIfExistsAsync(string streamName)
    {
        try
        {
            await ExecuteKsqlStatementAsync($"DROP STREAM IF EXISTS {streamName};");
        }
        catch { }
    }

    private async Task DropTableIfExistsAsync(string tableName)
    {
        try
        {
            await ExecuteKsqlStatementAsync($"DROP TABLE IF EXISTS {tableName};");
        }
        catch { }
    }

    private async Task WaitForStreamAsync(string streamName, int maxRetries = 10)
    {
        for (int i = 0; i < maxRetries; i++)
        {
            await Task.Delay(2000);
            try
            {
                var httpClient = new HttpClient { BaseAddress = new Uri(_ksqlDbUrl) };
                var payload = new { ksql = "SHOW STREAMS;" };
                var json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/vnd.ksql.v1+json");
                var response = await httpClient.PostAsync("/ksql", content);
                var body = await response.Content.ReadAsStringAsync();
                if (body.Contains(streamName, StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogInformation("Verified stream {Stream} exists (attempt {Attempt})", streamName, i + 1);
                    return;
                }
            }
            catch { }
            _logger.LogInformation("Waiting for stream {Stream}... (attempt {Attempt}/{Max})", streamName, i + 1, maxRetries);
        }
        _logger.LogWarning("Stream {Stream} not found after {Max} retries", streamName, maxRetries);
    }

    // Push Query: Stream verified transactions in real-time
    public async IAsyncEnumerable<VerifiedTransaction> StreamVerifiedTransactionsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (var item in RunPushQueryAsync<VerifiedTransaction>(
            "SELECT * FROM verified_transactions EMIT CHANGES;", cancellationToken))
        {
            yield return item;
        }
    }

    // Push Query: Stream fraud alerts in real-time
    public async IAsyncEnumerable<FraudAlert> StreamFraudAlertsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (var item in RunPushQueryAsync<FraudAlert>(
            "SELECT * FROM fraud_alerts EMIT CHANGES;", cancellationToken))
        {
            yield return item;
        }
    }

    // Pull Query: Get current account balance
    public async Task<AccountBalance?> GetAccountBalanceAsync(string accountId)
    {
        try
        {
            var httpClient = new HttpClient { BaseAddress = new Uri(_ksqlDbUrl) };
            var payload = new { ksql = $"SELECT * FROM account_balances WHERE account_id = '{accountId}';" };
            var json = JsonSerializer.Serialize(payload);
            var content = new StringContent(json, Encoding.UTF8, "application/vnd.ksql.v1+json");

            var response = await httpClient.PostAsync("/query", content);
            var body = await response.Content.ReadAsStringAsync();

            // ksqlDB returns an array of rows; parse the first data row
            var rows = JsonSerializer.Deserialize<JsonElement[]>(body);
            if (rows == null || rows.Length < 2) return null;

            // First element is header, second is data
            var row = rows[1];
            if (row.TryGetProperty("row", out var rowData) &&
                rowData.TryGetProperty("columns", out var columns))
            {
                return new AccountBalance
                {
                    AccountId = columns[0].GetString() ?? accountId,
                    Balance = columns[1].GetDecimal(),
                    TransactionCount = columns[2].GetInt32()
                };
            }
            return null;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Error querying balance for {AccountId}", accountId);
            return null;
        }
    }

    // Generic push query helper using raw HTTP streaming
    private async IAsyncEnumerable<T> RunPushQueryAsync<T>(string ksql,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var httpClient = new HttpClient { BaseAddress = new Uri(_ksqlDbUrl), Timeout = TimeSpan.FromHours(1) };
        var payload = new { ksql, streamsProperties = new Dictionary<string, string>() };
        var json = JsonSerializer.Serialize(payload);
        var content = new StringContent(json, Encoding.UTF8, "application/vnd.ksql.v1+json");

        var request = new HttpRequestMessage(HttpMethod.Post, "/query") { Content = content };
        var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new StreamReader(stream);

        // First line is the header (column names)
        await reader.ReadLineAsync(cancellationToken);

        while (!cancellationToken.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(cancellationToken);
            if (line == null) break;
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith("[")) continue;

            // Each data line is a JSON object like {"row":{"columns":[...]}}
            if (line.TrimEnd(',').Contains("\"row\""))
            {
                var parsed = TryParseRow<T>(line);
                if (parsed != null) yield return parsed;
            }
        }
    }

    private T? TryParseRow<T>(string line)
    {
        try
        {
            var element = JsonSerializer.Deserialize<JsonElement>(line.TrimEnd(','));
            if (element.TryGetProperty("row", out var rowData) &&
                rowData.TryGetProperty("columns", out var columns))
            {
                return JsonSerializer.Deserialize<T>(columns.GetRawText());
            }
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Error parsing push query row: {Line}", line);
        }
        return default;
    }

    public KSqlDBContext Context => _context;
}
