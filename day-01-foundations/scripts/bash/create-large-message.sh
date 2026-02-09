#!/bin/bash
# =============================================================================
# Create Large Message Test Data
# =============================================================================

set -e

# --- Config ---
OUTPUT_FILE="../data/large-message.json"

# --- Helper functions ---
write_info() { echo "INFO: $1" ; }

# --- Main Script ---
write_info "Creating large message test data..."

# Generate a very long description to create a large message
LONG_DESCRIPTION=""
for i in {1..1000}; do
    LONG_DESCRIPTION+="This is part $i of a very long description that will significantly increase the message size. "
done

cat > "$OUTPUT_FILE" << EOF
{
  "fromAccount": "FR7630001000111111",
  "toAccount": "FR7630001000222222",
  "amount": 999999.99,
  "currency": "EUR",
  "type": 1,
  "description": "$LONG_DESCRIPTION",
  "customerId": "CUST-LARGE-001",
  "transactionId": "TX-LARGE-$(date +%s)",
  "metadata": {
    "source": "large-message-generator",
    "priority": "high",
    "tags": ["large", "test", "performance"],
    "additionalData": "$(openssl rand -base64 50000 2>/dev/null || echo 'X$(printf 'A%.0s' {1..50000})')",
    "payload": "$(printf 'Large payload data - %.0s' {1..10000})END"
  }
}
EOF

write_info "Large message data created: $OUTPUT_FILE"
write_info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
