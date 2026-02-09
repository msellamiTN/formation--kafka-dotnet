package com.data2ai.kafka.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public class Order {
    
    @JsonProperty("orderId")
    private String orderId;
    
    @JsonProperty("amount")
    private double amount;
    
    @JsonProperty("status")
    private String status;

    public Order() {}

    public Order(String orderId, double amount, String status) {
        this.orderId = orderId;
        this.amount = amount;
        this.status = status;
    }

    public String getOrderId() { return orderId; }
    public void setOrderId(String orderId) { this.orderId = orderId; }

    public double getAmount() { return amount; }
    public void setAmount(double amount) { this.amount = amount; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public void validate() throws IllegalArgumentException {
        if (orderId == null || orderId.isEmpty()) {
            throw new IllegalArgumentException("Order ID is required");
        }
        if (amount < 0) {
            throw new IllegalArgumentException("Amount cannot be negative: " + amount);
        }
    }
}
