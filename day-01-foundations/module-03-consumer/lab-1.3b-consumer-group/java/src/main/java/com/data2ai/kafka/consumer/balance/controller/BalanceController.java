package com.data2ai.kafka.consumer.balance.controller;

import com.data2ai.kafka.consumer.balance.model.CustomerBalance;
import com.data2ai.kafka.consumer.balance.model.RebalancingEvent;
import com.data2ai.kafka.consumer.balance.service.BalanceService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class BalanceController {

    private final BalanceService balanceService;

    public BalanceController(BalanceService balanceService) {
        this.balanceService = balanceService;
    }

    @GetMapping("/balances")
    public ResponseEntity<Map<String, CustomerBalance>> allBalances() {
        return ResponseEntity.ok(balanceService.getBalances());
    }

    @GetMapping("/balances/{customerId}")
    public ResponseEntity<CustomerBalance> balance(@PathVariable String customerId) {
        CustomerBalance bal = balanceService.getBalance(customerId);
        if (bal == null) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(bal);
    }

    @GetMapping("/rebalancing")
    public ResponseEntity<List<RebalancingEvent>> rebalancingHistory() {
        return ResponseEntity.ok(balanceService.getRebalancingHistory());
    }

    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> stats() {
        return ResponseEntity.ok(balanceService.getMetrics());
    }
}
