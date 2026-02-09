# Create a message that passes validation but exceeds Kafka's message size limit
# We'll create many transactions in a batch to exceed the size limit

$transactions = @()
for ($i = 1; $i -le 5000; $i++) {
    $transactions += @{
        fromAccount = "FR7630001000111111111"
        toAccount = "FR7630001000222222222"
        amount = 100.0
        currency = "EUR"
        type = 1
        description = "Transaction $i description to increase size"
        customerId = "CUST-OVERSIZE-$i"
    }
}

$json = $transactions | ConvertTo-Json -Depth 10

Set-Content -Path "oversized-valid.json" -Value $json
Write-Host "Created batch with $($transactions.Count) transactions"
Write-Host "JSON size: $([System.Text.Encoding]::UTF8.GetByteCount($json)) bytes"
