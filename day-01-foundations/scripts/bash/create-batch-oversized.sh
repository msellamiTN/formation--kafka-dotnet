#!/bin/bash
# =============================================================================
# Create Oversized Batch Test Data
# =============================================================================

set -e

# --- Config ---
OUTPUT_FILE="../data/batch-oversized.json"
RECORD_COUNT=500

# --- Helper functions ---
write_info() { echo "INFO: $1" ; }

# --- Main Script ---
write_info "Creating oversized batch test data with $RECORD_COUNT records..."

cat > "$OUTPUT_FILE" << 'EOF'
[
EOF

for i in $(seq 1 $RECORD_COUNT); do
    CUSTOMER_ID="CUST-$(printf "%03d" $(( (i-1) % 20 + 1 )))"
    AMOUNT=$(echo "scale=2; $(( (i-1) % 5000 + 1 )) * 25.75" | bc)
    CURRENCY=$([ $((i % 4)) -eq 0 ] && echo "GBP" || [ $((i % 3)) -eq 0 ] && echo "USD" || echo "EUR")
    
    # Create a long description to increase message size
    LONG_DESC="This is a very long description for transaction number $i that includes many details about the transaction purpose, reference numbers, additional metadata, and other information that will increase the overall message size significantly for testing purposes with large payloads and batch processing scenarios. Transaction reference: REF-$(printf "%08d" $i)-BATCH-OVERSIZED."
    
    cat >> "$OUTPUT_FILE" << EOF
  {
    "fromAccount": "FR7630001000$(printf "%07d" $((i * 3333 % 9999999)))",
    "toAccount": "FR7630001000$(printf "%07d" $((i * 4444 % 9999999)))",
    "amount": $AMOUNT,
    "currency": "$CURRENCY",
    "type": $((i % 4 + 1)),
    "description": "$LONG_DESC",
    "customerId": "$CUSTOMER_ID",
    "transactionId": "TX-OVERSIZED-$(printf "%06d" $i)",
    "metadata": {
      "source": "batch-generator",
      "batchId": "BATCH-$(date +%s)",
      "priority": $((i % 3)),
      "tags": ["test", "oversized", "batch", "tag-$((i % 10))"],
      "additionalInfo": "Additional metadata field to increase message size for testing large message handling capabilities and performance characteristics under heavy load conditions."
    }
  }$([ $i -lt $RECORD_COUNT ] && echo "," || echo "")
EOF
done

cat >> "$OUTPUT_FILE" << 'EOF'
]
EOF

write_info "Oversized batch data created: $OUTPUT_FILE"
write_info "Records: $RECORD_COUNT"
write_info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
