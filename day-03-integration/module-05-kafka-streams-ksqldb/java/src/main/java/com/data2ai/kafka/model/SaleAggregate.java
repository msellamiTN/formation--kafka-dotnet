package com.data2ai.kafka.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public class SaleAggregate {
    @JsonProperty("count")
    private long count;
    
    @JsonProperty("totalAmount")
    private double totalAmount;
    
    @JsonProperty("totalQuantity")
    private long totalQuantity;

    public SaleAggregate() {
        this.count = 0;
        this.totalAmount = 0.0;
        this.totalQuantity = 0;
    }

    public SaleAggregate add(Sale sale) {
        this.count++;
        this.totalAmount += sale.getTotalAmount();
        this.totalQuantity += sale.getQuantity();
        return this;
    }

    public long getCount() { return count; }
    public void setCount(long count) { this.count = count; }

    public double getTotalAmount() { return totalAmount; }
    public void setTotalAmount(double totalAmount) { this.totalAmount = totalAmount; }

    public long getTotalQuantity() { return totalQuantity; }
    public void setTotalQuantity(long totalQuantity) { this.totalQuantity = totalQuantity; }
}
