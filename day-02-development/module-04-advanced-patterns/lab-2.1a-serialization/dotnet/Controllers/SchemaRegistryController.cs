using Microsoft.AspNetCore.Mvc;
using EBankingSerializationAPI.Services;

namespace EBankingSerializationAPI.Controllers;

/// <summary>
/// Schema Registry management endpoints for registering, retrieving,
/// and validating schemas used by Kafka producers and consumers.
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class SchemaRegistryController : ControllerBase
{
    private readonly SchemaRegistryService _schemaRegistryService;
    private readonly ILogger<SchemaRegistryController> _logger;

    public SchemaRegistryController(
        SchemaRegistryService schemaRegistryService,
        ILogger<SchemaRegistryController> logger)
    {
        _schemaRegistryService = schemaRegistryService;
        _logger = logger;
    }

    /// <summary>
    /// Test connectivity to Schema Registry
    /// </summary>
    [HttpGet("health")]
    public async Task<IActionResult> HealthCheck()
    {
        var connected = await _schemaRegistryService.TestConnectionAsync();
        if (connected)
        {
            return Ok(new
            {
                status = "connected",
                service = "schema-registry",
                timestamp = DateTime.UtcNow
            });
        }

        return StatusCode(503, new
        {
            status = "disconnected",
            service = "schema-registry",
            timestamp = DateTime.UtcNow,
            message = "Cannot reach Schema Registry"
        });
    }

    /// <summary>
    /// Get Schema Registry configuration and status
    /// </summary>
    [HttpGet("config")]
    public async Task<IActionResult> GetConfig()
    {
        try
        {
            var config = await _schemaRegistryService.GetConfigInfoAsync();
            return Ok(config);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get Schema Registry config");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// List all registered subjects in Schema Registry
    /// </summary>
    [HttpGet("subjects")]
    public async Task<IActionResult> ListSubjects()
    {
        try
        {
            var subjects = await _schemaRegistryService.ListSubjectsAsync();
            return Ok(new
            {
                count = subjects.Count,
                subjects
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to list subjects");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Get the latest transaction schema
    /// </summary>
    [HttpGet("schemas/transactions/latest")]
    public async Task<IActionResult> GetLatestTransactionSchema()
    {
        try
        {
            var schemaJson = await _schemaRegistryService.GetLatestTransactionSchemaAsync();
            return Ok(new
            {
                subject = "ebanking.transactions-value",
                schema = schemaJson
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get latest transaction schema");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Get schema by ID
    /// </summary>
    [HttpGet("schemas/{schemaId}")]
    public async Task<IActionResult> GetSchemaById(int schemaId)
    {
        try
        {
            var schemaJson = await _schemaRegistryService.GetSchemaByIdAsync(schemaId);
            return Ok(new
            {
                schemaId,
                schema = schemaJson
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get schema {SchemaId}", schemaId);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Get schema versions for a subject (e.g. "transactions")
    /// </summary>
    [HttpGet("schemas/{subjectName}/versions")]
    public async Task<IActionResult> GetSchemaVersions(string subjectName)
    {
        try
        {
            var versions = await _schemaRegistryService.GetSchemaVersionsAsync(subjectName);
            return Ok(new
            {
                subject = subjectName,
                count = versions.Count,
                versions
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get schema versions for {SubjectName}", subjectName);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Register a new transaction schema (v1 or v2)
    /// </summary>
    [HttpPost("schemas/register")]
    public async Task<IActionResult> RegisterSchema([FromBody] RegisterSchemaRequest request)
    {
        try
        {
            string schemaJson;

            if (request.Version == "v2")
            {
                schemaJson = GetTransactionV2SchemaJson();
            }
            else
            {
                schemaJson = GetTransactionV1SchemaJson();
            }

            var schemaId = await _schemaRegistryService.RegisterTransactionSchemaAsync(schemaJson, request.Version);

            return Ok(new
            {
                schemaId,
                version = request.Version,
                subject = "ebanking.transactions-value",
                status = "registered"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register schema version {Version}", request.Version);
            return StatusCode(500, new { error = ex.Message });
        }
    }

    /// <summary>
    /// Register a custom schema (raw JSON schema string)
    /// </summary>
    [HttpPost("schemas/register-custom")]
    public async Task<IActionResult> RegisterCustomSchema([FromBody] RegisterCustomSchemaRequest request)
    {
        try
        {
            var schemaId = await _schemaRegistryService.RegisterTransactionSchemaAsync(
                request.SchemaJson, request.Version ?? "custom");

            return Ok(new
            {
                schemaId,
                version = request.Version,
                subject = "ebanking.transactions-value",
                status = "registered"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to register custom schema");
            return StatusCode(500, new { error = ex.Message });
        }
    }

    private string GetTransactionV1SchemaJson()
    {
        return @"{
            ""type"": ""record"",
            ""name"": ""Transaction"",
            ""namespace"": ""ebanking"",
            ""fields"": [
                {""name"": ""transactionId"", ""type"": ""string""},
                {""name"": ""customerId"", ""type"": ""string""},
                {""name"": ""fromAccount"", ""type"": ""string""},
                {""name"": ""toAccount"", ""type"": ""string""},
                {""name"": ""amount"", ""type"": ""double""},
                {""name"": ""currency"", ""type"": ""string""},
                {""name"": ""type"", ""type"": ""int""},
                {""name"": ""description"", ""type"": [""null"", ""string""], ""default"": null},
                {""name"": ""timestamp"", ""type"": ""string""}
            ]
        }";
    }

    private string GetSchemaType() => "AVRO";

    private string GetTransactionV2SchemaJson()
    {
        return @"{
            ""type"": ""record"",
            ""name"": ""TransactionV2"",
            ""namespace"": ""ebanking"",
            ""fields"": [
                {""name"": ""transactionId"", ""type"": ""string""},
                {""name"": ""customerId"", ""type"": ""string""},
                {""name"": ""fromAccount"", ""type"": ""string""},
                {""name"": ""toAccount"", ""type"": ""string""},
                {""name"": ""amount"", ""type"": ""double""},
                {""name"": ""currency"", ""type"": ""string""},
                {""name"": ""type"", ""type"": ""int""},
                {""name"": ""description"", ""type"": [""null"", ""string""], ""default"": null},
                {""name"": ""timestamp"", ""type"": ""string""},
                {""name"": ""riskScore"", ""type"": [""null"", ""double""], ""default"": null},
                {""name"": ""sourceChannel"", ""type"": [""null"", ""string""], ""default"": null}
            ]
        }";
    }
}

public class RegisterSchemaRequest
{
    public string Version { get; set; } = "v1";
}

public class RegisterCustomSchemaRequest
{
    public string SchemaJson { get; set; } = "";
    public string? Version { get; set; }
}
