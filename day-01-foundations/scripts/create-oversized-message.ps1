# Create a message that passes validation but exceeds Kafka's default max message size (1MB)
$desc = "B" * 900000  # 900KB description, within validation limits
$json = @{
    fromAccount = "FR7630001000111111111"
    toAccount = "FR7630001000222222222"
    amount = 100.0
    currency = "EUR"
    type = 1
    description = $desc
    customerId = "CUST-OVERSIZE-001"
} | ConvertTo-Json -Depth 10
Set-Content -Path "oversized-message.json" -Value $json
Write-Host "Created oversized message with description length: $($desc.Length)"
