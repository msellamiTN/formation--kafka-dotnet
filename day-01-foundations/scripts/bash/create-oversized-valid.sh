#!/bin/bash
# =============================================================================
# Create Valid Oversized Message Test Data
# =============================================================================

set -e

# --- Config ---
OUTPUT_FILE="../data/oversized-valid.json"

# --- Helper functions ---
write_info() { echo "INFO: $1" ; }

# --- Main Script ---
write_info "Creating valid oversized message test data..."

# Generate a large but valid payload
VALID_LARGE_PAYLOAD=""
for i in {1..2000}; do
    VALID_LARGE_PAYLOAD+="Valid large payload segment $i with proper formatting and structure. "
done

cat > "$OUTPUT_FILE" << EOF
{
  "fromAccount": "FR7630001000111111",
  "toAccount": "FR7630001000222222",
  "amount": 500000.00,
  "currency": "EUR",
  "type": 1,
  "description": "This is a large but valid message for testing performance and throughput. $VALID_LARGE_PAYLOAD",
  "customerId": "CUST-LARGE-VALID-001",
  "transactionId": "TX-LARGE-VALID-$(date +%s)",
  "metadata": {
    "source": "valid-oversized-generator",
    "priority": "normal",
    "tags": ["large", "valid", "performance", "throughput"],
    "validLargeData": "$(printf 'Valid data chunk %.0s' {1..50000})",
    "structuredPayload": {
      "section1": "$(for i in {1..1000}; do echo -n "Section1-$i "; done)",
      "section2": "$(for i in {1..1000}; do echo -n "Section2-$i "; done)",
      "section3": "$(for i in {1..1000}; do echo -n "Section3-$i "; done)"
    },
    "arrayData": [
      $(for i in {1..500}; do echo "\"array-item-$i\""; done | tr '\n' ',' | sed 's/,$//')
    ]
  },
  "additionalInfo": "This message is large but properly structured and should be handled correctly by the Kafka producer and consumer."
}
EOF

write_info "Valid oversized message data created: $OUTPUT_FILE"
write_info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
