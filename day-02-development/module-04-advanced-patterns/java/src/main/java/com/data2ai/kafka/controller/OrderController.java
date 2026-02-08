package com.data2ai.kafka.controller;

import com.data2ai.kafka.model.Order;
import com.data2ai.kafka.service.DltService;
import com.data2ai.kafka.service.OrderService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class OrderController {

    private final OrderService orderService;
    private final DltService dltService;

    public OrderController(OrderService orderService, DltService dltService) {
        this.orderService = orderService;
        this.dltService = dltService;
    }

    @PostMapping("/orders")
    public ResponseEntity<?> createOrder(@RequestBody Order order) {
        try {
            orderService.sendOrder(order);
            return ResponseEntity.ok(Map.of(
                "status", "ACCEPTED",
                "orderId", order.getOrderId(),
                "message", "Order sent to Kafka"
            ));
        } catch (OrderService.PermanentException e) {
            return ResponseEntity.badRequest().body(Map.of(
                "status", "REJECTED",
                "orderId", order.getOrderId(),
                "error", e.getMessage(),
                "action", "Sent to DLT"
            ));
        } catch (OrderService.TransientException e) {
            return ResponseEntity.status(503).body(Map.of(
                "status", "RETRY",
                "orderId", order.getOrderId(),
                "error", e.getMessage()
            ));
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of(
                "status", "ERROR",
                "error", e.getMessage()
            ));
        }
    }

    @PostMapping("/config/simulate-transient-error")
    public ResponseEntity<?> setTransientErrorSimulation(@RequestParam boolean enabled) {
        orderService.setSimulateTransientError(enabled);
        return ResponseEntity.ok(Map.of(
            "simulateTransientError", enabled,
            "message", enabled ? "Transient errors enabled" : "Transient errors disabled"
        ));
    }

    @GetMapping("/config/simulate-transient-error")
    public ResponseEntity<?> getTransientErrorSimulation() {
        return ResponseEntity.ok(Map.of(
            "simulateTransientError", orderService.isSimulatingTransientError()
        ));
    }

    @GetMapping("/stats")
    public ResponseEntity<?> getStats() {
        OrderService.Stats stats = orderService.getStats();
        return ResponseEntity.ok(Map.of(
            "success", stats.success,
            "errors", stats.errors,
            "dlt", stats.dlt
        ));
    }

    @GetMapping("/dlt/count")
    public ResponseEntity<?> getDltCount() {
        return ResponseEntity.ok(Map.of(
            "dltCount", dltService.getDltCount()
        ));
    }

    @GetMapping("/health")
    public ResponseEntity<?> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }
}
