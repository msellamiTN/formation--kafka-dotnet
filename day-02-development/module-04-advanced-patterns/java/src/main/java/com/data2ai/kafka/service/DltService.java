package com.data2ai.kafka.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class DltService {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    @Value("${KAFKA_DLT_TOPIC:orders.DLT}")
    private String dltTopic;

    private final AtomicLong dltMessageCount = new AtomicLong(0);

    public DltService(KafkaTemplate<String, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    public void sendToDlt(Object originalMessage, Throwable error, String originalTopic, int retryCount) {
        try {
            Map<String, Object> dltMessage = new HashMap<>();
            dltMessage.put("originalTopic", originalTopic);
            dltMessage.put("originalValue", objectMapper.writeValueAsString(originalMessage));
            dltMessage.put("errorMessage", error.getMessage());
            dltMessage.put("errorClass", error.getClass().getName());
            dltMessage.put("errorTimestamp", Instant.now().toString());
            dltMessage.put("retryCount", retryCount);
            
            StackTraceElement[] stackTrace = error.getStackTrace();
            if (stackTrace.length > 0) {
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < Math.min(5, stackTrace.length); i++) {
                    sb.append(stackTrace[i].toString()).append("\n");
                }
                dltMessage.put("stackTrace", sb.toString());
            }

            String dltValue = objectMapper.writeValueAsString(dltMessage);
            String key = "dlt-" + Instant.now().toEpochMilli();

            kafkaTemplate.send(dltTopic, key, dltValue)
                .whenComplete((result, ex) -> {
                    if (ex == null) {
                        dltMessageCount.incrementAndGet();
                        System.out.println("Message sent to DLT: " + key + 
                            " partition=" + result.getRecordMetadata().partition() +
                            " offset=" + result.getRecordMetadata().offset());
                    } else {
                        System.err.println("Failed to send to DLT: " + ex.getMessage());
                    }
                });

        } catch (Exception e) {
            System.err.println("Error creating DLT message: " + e.getMessage());
        }
    }

    public long getDltCount() {
        return dltMessageCount.get();
    }
}
