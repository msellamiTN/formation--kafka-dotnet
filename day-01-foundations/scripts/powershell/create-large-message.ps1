$desc = "A" * 1000000
$json = @{
    fromAccount = "FR7630001000111111111"
    toAccount = "FR7630001000222222222"
    amount = 100.0
    currency = "EUR"
    type = 1
    description = $desc
    customerId = "CUST-LARGE-001"
} | ConvertTo-Json -Depth 10
Set-Content -Path "large-message.json" -Value $json
