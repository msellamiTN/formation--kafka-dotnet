using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace EBankingSerializationAPI.Services;

/// <summary>
/// Schema Registry service using Apicurio Registry (Confluent-compatible API).
/// Manages JSON schemas for Kafka topics via the /apis/ccompat/v7 endpoint.
/// </summary>
public class SchemaRegistryService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<SchemaRegistryService> _logger;
    private readonly string _baseUrl;
    private readonly string _compatBase;
    private readonly string _subjectPrefix;

    public SchemaRegistryService(
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration,
        ILogger<SchemaRegistryService> logger)
    {
        _logger = logger;
        _httpClient = httpClientFactory.CreateClient();
        _baseUrl = configuration["SchemaRegistry:Url"] ?? "http://schema-registry:8081";
        _compatBase = $"{_baseUrl}/apis/ccompat/v7";
        _subjectPrefix = configuration["SchemaRegistry:SubjectPrefix"] ?? "ebanking";
    }

    /// <summary>
    /// Register a new schema for a subject
    /// </summary>
    public async Task<int> RegisterTransactionSchemaAsync(string schemaJson, string version = "v1")
    {
        try
        {
            var subject = $"{_subjectPrefix}.transactions-value";
            var payload = new { schema = schemaJson, schemaType = "AVRO" };
            var content = new StringContent(
                JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

            var response = await _httpClient.PostAsync(
                $"{_compatBase}/subjects/{subject}/versions", content);
            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<JsonElement>(body);
            var schemaId = result.GetProperty("id").GetInt32();

            _logger.LogInformation("Registered schema {SchemaId} for subject {Subject} version {Version}",
                schemaId, subject, version);
            return schemaId;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register schema for version {Version}", version);
            throw;
        }
    }

    /// <summary>
    /// Get the latest schema for transactions
    /// </summary>
    public async Task<string> GetLatestTransactionSchemaAsync()
    {
        var subject = $"{_subjectPrefix}.transactions-value";
        try
        {
            var response = await _httpClient.GetAsync(
                $"{_compatBase}/subjects/{subject}/versions/latest");
            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<JsonElement>(body);
            return result.GetProperty("schema").GetString() ?? "";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get latest schema for {Subject}", subject);
            throw;
        }
    }

    /// <summary>
    /// Get schema by global ID
    /// </summary>
    public async Task<string> GetSchemaByIdAsync(int schemaId)
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_compatBase}/schemas/ids/{schemaId}");
            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync();
            var result = JsonSerializer.Deserialize<JsonElement>(body);
            return result.GetProperty("schema").GetString() ?? "";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get schema {SchemaId}", schemaId);
            throw;
        }
    }

    /// <summary>
    /// List all subjects
    /// </summary>
    public async Task<List<string>> ListSubjectsAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_compatBase}/subjects");
            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<List<string>>(body) ?? new List<string>();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to list subjects");
            throw;
        }
    }

    /// <summary>
    /// Get schema versions for a subject
    /// </summary>
    public async Task<List<int>> GetSchemaVersionsAsync(string subjectName)
    {
        var fullSubject = $"{_subjectPrefix}.{subjectName}-value";
        try
        {
            var response = await _httpClient.GetAsync(
                $"{_compatBase}/subjects/{fullSubject}/versions");
            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<List<int>>(body) ?? new List<int>();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get versions for {Subject}", fullSubject);
            throw;
        }
    }

    /// <summary>
    /// Test connectivity to Schema Registry
    /// </summary>
    public async Task<bool> TestConnectionAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync($"{_baseUrl}/health/ready");
            _logger.LogInformation("Schema Registry health check: {StatusCode}", response.StatusCode);
            return response.IsSuccessStatusCode;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Schema Registry connection failed");
            return false;
        }
    }

    /// <summary>
    /// Get schema registry configuration and status
    /// </summary>
    public async Task<object> GetConfigInfoAsync()
    {
        try
        {
            var connected = await TestConnectionAsync();
            var subjects = connected ? await ListSubjectsAsync() : new List<string>();

            return new
            {
                connected,
                registryType = "Apicurio Registry (Confluent-compatible)",
                url = _baseUrl,
                compatApiUrl = _compatBase,
                subjectPrefix = _subjectPrefix,
                totalSubjects = subjects.Count,
                subjects = subjects.Where(s => s.StartsWith(_subjectPrefix)).ToList()
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get config info");
            return new
            {
                connected = false,
                error = ex.Message
            };
        }
    }
}
