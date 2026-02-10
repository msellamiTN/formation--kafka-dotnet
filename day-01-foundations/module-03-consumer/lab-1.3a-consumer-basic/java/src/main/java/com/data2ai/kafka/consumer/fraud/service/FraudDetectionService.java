package com.data2ai.kafka.consumer.fraud.service;

import com.data2ai.kafka.consumer.fraud.model.FraudAlert;
import com.data2ai.kafka.consumer.fraud.model.Transaction;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class FraudDetectionService {

    private static final Logger log = LoggerFactory.getLogger(FraudDetectionService.class);

    private final ObjectMapper objectMapper;

    private final List<FraudAlert> alerts = new ArrayList<>();

    private final AtomicLong messagesConsumed = new AtomicLong();
    private final AtomicLong fraudAlerts = new AtomicLong();
    private final AtomicLong processingErrors = new AtomicLong();

    private volatile double totalRiskScore = 0.0;
    private final Instant startedAt = Instant.now();
    private volatile Instant lastMessageAt;

    public FraudDetectionService(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @KafkaListener(topics = "${app.kafka.topic}")
    public void onMessage(ConsumerRecord<String, String> record) {
        messagesConsumed.incrementAndGet();
        lastMessageAt = Instant.now();

        try {
            Transaction tx = objectMapper.readValue(record.value(), Transaction.class);

            int score = tx.getRiskScore() != null ? tx.getRiskScore() : computeRiskScore(tx);
            totalRiskScore += score;

            if (score >= 70) {
                FraudAlert alert = new FraudAlert();
                alert.setAlertId("ALERT-" + UUID.randomUUID().toString().substring(0, 8));
                alert.setTransactionId(tx.getTransactionId());
                alert.setCustomerId(tx.getCustomerId());
                alert.setRiskScore(score);
                alert.setReason("High risk transaction");
                alert.setCreatedAt(Instant.now());

                synchronized (alerts) {
                    alerts.add(alert);
                    // Keep memory bounded for lab usage
                    if (alerts.size() > 500) {
                        alerts.remove(0);
                    }
                }

                fraudAlerts.incrementAndGet();
                log.warn("Fraud alert: txId={} customerId={} riskScore={} partition={} offset={} ",
                        tx.getTransactionId(), tx.getCustomerId(), score,
                        record.partition(), record.offset());
            } else {
                log.debug("Transaction ok: txId={} customerId={} riskScore={} partition={} offset={}",
                        tx.getTransactionId(), tx.getCustomerId(), score,
                        record.partition(), record.offset());
            }
        } catch (Exception ex) {
            processingErrors.incrementAndGet();
            log.error("Processing error. partition={} offset={} error={}",
                    record.partition(), record.offset(), ex.getMessage());
        }
    }

    public List<FraudAlert> getAlerts() {
        synchronized (alerts) {
            return new ArrayList<>(alerts);
        }
    }

    public FraudMetrics getMetrics() {
        FraudMetrics m = new FraudMetrics();
        m.setMessagesConsumed(messagesConsumed.get());
        m.setFraudAlerts(fraudAlerts.get());
        m.setProcessingErrors(processingErrors.get());
        m.setStartedAt(startedAt);
        m.setLastMessageAt(lastMessageAt);

        long count = messagesConsumed.get();
        m.setAverageRiskScore(count > 0 ? (totalRiskScore / count) : 0.0);
        return m;
    }

    private int computeRiskScore(Transaction tx) {
        // Simple heuristic for training: higher amount => higher risk.
        if (tx.getAmount() == null) return 0;

        double amount = tx.getAmount().doubleValue();
        if (amount >= 10_000) return 90;
        if (amount >= 5_000) return 70;
        if (amount >= 1_000) return 40;
        return 10;
    }
}
