package com.data2ai.kafka.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Sale {
    @JsonProperty("productId")
    private String productId;
    
    @JsonProperty("quantity")
    private int quantity;
    
    @JsonProperty("unitPrice")
    private double unitPrice;
    
    @JsonProperty("timestamp")
    private long timestamp;

    public Sale() {
        this.timestamp = System.currentTimeMillis();
    }

    public Sale(String productId, int quantity, double unitPrice) {
        this.productId = productId;
        this.quantity = quantity;
        this.unitPrice = unitPrice;
        this.timestamp = System.currentTimeMillis();
    }

    public String getProductId() { return productId; }
    public void setProductId(String productId) { this.productId = productId; }

    public int getQuantity() { return quantity; }
    public void setQuantity(int quantity) { this.quantity = quantity; }

    public double getUnitPrice() { return unitPrice; }
    public void setUnitPrice(double unitPrice) { this.unitPrice = unitPrice; }

    public long getTimestamp() { return timestamp; }
    public void setTimestamp(long timestamp) { this.timestamp = timestamp; }

    public double getTotalAmount() {
        return quantity * unitPrice;
    }
}
