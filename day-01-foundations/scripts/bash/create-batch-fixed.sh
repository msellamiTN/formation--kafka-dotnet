#!/bin/bash
# =============================================================================
# Create Fixed Batch Test Data
# =============================================================================

set -e

# --- Config ---
OUTPUT_FILE="../data/batch-fixed.json"
RECORD_COUNT=100

# --- Helper functions ---
write_info() { echo "INFO: $1" ; }

# --- Main Script ---
write_info "Creating fixed batch test data with $RECORD_COUNT records..."

cat > "$OUTPUT_FILE" << 'EOF'
[
EOF

for i in $(seq 1 $RECORD_COUNT); do
    CUSTOMER_ID="CUST-$(printf "%03d" $(( (i-1) % 10 + 1 )))"
    AMOUNT=$(echo "scale=2; $(( (i-1) % 1000 + 1 )) * 10.50" | bc)
    CURRENCY=$([ $((i % 3)) -eq 0 ] && echo "USD" || echo "EUR")
    
    cat >> "$OUTPUT_FILE" << EOF
  {
    "fromAccount": "FR7630001000$(printf "%07d" $((i * 1111 % 9999999)))",
    "toAccount": "FR7630001000$(printf "%07d" $((i * 2222 % 9999999)))",
    "amount": $AMOUNT,
    "currency": "$CURRENCY",
    "type": $((i % 3 + 1)),
    "description": "Batch transaction $i",
    "customerId": "$CUSTOMER_ID",
    "transactionId": "TX-BATCH-$(printf "%06d" $i)"
  }$([ $i -lt $RECORD_COUNT ] && echo "," || echo "")
EOF
done

cat >> "$OUTPUT_FILE" << 'EOF'
]
EOF

write_info "Fixed batch data created: $OUTPUT_FILE"
write_info "Records: $RECORD_COUNT"
write_info "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
