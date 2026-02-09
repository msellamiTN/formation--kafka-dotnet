#!/bin/bash
# =============================================================================
# Create Oversized Message Test Data
# =============================================================================

set -e

# --- Config ---
OUTPUT_FILE="../data/oversized-message.json"

# --- Helper functions ---
write_info() { echo "INFO: $1" ; }

# --- Main Script ---
write_info "Creating oversized message test data..."

# Generate an extremely large payload
LARGE_PAYLOAD=""
for i in {1..5000}; do
    LARGE_PAYLOAD+="Oversized payload chunk $i - This is designed to exceed Kafka's default message size limits and test error handling capabilities. "
done

cat > "$OUTPUT_FILE" << EOF
{
  "fromAccount": "FR7630001000111111",
  "toAccount": "FR7630001000222222",
  "amount": 9999999.99,
  "currency": "EUR",
  "type": 1,
  "description": "This is an oversized message designed to test Kafka's message size limits and error handling mechanisms. $LARGE_PAYLOAD",
  "customerId": "CUST-OVERSIZED-001",
  "transactionId": "TX-OVERSIZED-$(date +%s)",
  "metadata": {
    "source": "oversized-message-generator",
    "priority": "critical",
    "tags": ["oversized", "test", "error-handling", "size-limit"],
    "hugePayload": "$(printf 'X%.0s' {1..100000})",
    "massiveData": "$(openssl rand -base64 200000 2>/dev/null || printf 'Y%.0s' {1..200000})",
    "enormousString": "$(for i in {1..10000}; do echo -n "Massive string segment $i - "; done)"
  },
  "extraLargeField": "$(for i in {1..5000}; do echo -n "Extra large content $i: "; printf 'A%.0s' {1..100}; echo; done)"
}
EOF

write_info "Oversized message data created: $OUTPUT_FILE"
write_info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
