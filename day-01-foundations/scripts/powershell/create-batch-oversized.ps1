# Create a batch of transactions that together exceed Kafka's message size
$transactions = @()
for ($i = 1; $i -le 1000; $i++) {
    $transactions += @{
        fromAccount = "FR7630001000111111111"
        toAccount = "FR7630001000222222222"
        amount = 100.0
        currency = "EUR"
        type = 1
        description = "Batch transaction $i with maximum allowed description length to test size limits"
        customerId = "CUST-BATCH-001"
    }
}

$json = @{
    transactions = $transactions
} | ConvertTo-Json -Depth 10

Set-Content -Path "batch-oversized.json" -Value $json
Write-Host "Created batch with $($transactions.Count) transactions"
Write-Host "JSON size: $([System.Text.Encoding]::UTF8.GetByteCount($json)) bytes"
