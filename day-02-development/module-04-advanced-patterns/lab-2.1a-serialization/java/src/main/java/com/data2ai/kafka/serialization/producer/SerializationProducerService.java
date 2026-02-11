package com.data2ai.kafka.serialization.producer;

import com.data2ai.kafka.serialization.model.Transaction;
import com.data2ai.kafka.serialization.model.TransactionV2;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class SerializationProducerService {
    
    private static final Logger log = LoggerFactory.getLogger(SerializationProducerService.class);
    
    private final KafkaTemplate<String, Transaction> kafkaTemplate;
    
    @Value("${app.kafka.topic:banking.transactions}")
    private String topic;
    
    public SerializationProducerService(KafkaTemplate<String, Transaction> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }
    
    public void sendTransaction(Transaction transaction) {
        try {
            // Set transaction metadata
            transaction.setTransactionId(UUID.randomUUID().toString());
            transaction.setTimestamp(Instant.now());
            transaction.setStatus(Transaction.TransactionStatus.PENDING);
            
            // Use customer ID as key for partitioning
            String key = transaction.getCustomerId();
            
            log.info("Sending transaction: {} | Amount: {} {} | Customer: {}",
                    transaction.getTransactionId(),
                    transaction.getAmount(),
                    transaction.getCurrency(),
                    transaction.getCustomerId());

            kafkaTemplate.send(topic, key, transaction);
            
            transaction.setStatus(Transaction.TransactionStatus.COMPLETED);
            log.info("Transaction sent successfully: {}", transaction.getTransactionId());
            
        } catch (Exception e) {
            transaction.setStatus(Transaction.TransactionStatus.FAILED);
            log.error("Failed to send transaction: {} | Error: {}",
                    transaction.getTransactionId(), e.getMessage());
            throw new RuntimeException("Failed to prepare transaction", e);
        }
    }
    
    public void sendTransactionWithSchemaV2(TransactionV2 transactionV2) {
        try {
            // Convert V2 to V1 for backward compatibility
            Transaction transaction = convertV2ToV1(transactionV2);
            sendTransaction(transaction);
        } catch (Exception e) {
            log.error("Failed to send V2 transaction", e);
            throw new RuntimeException("Failed to send V2 transaction", e);
        }
    }
    
    public void sendTransactionBatch(List<Transaction> transactions) {
        for (Transaction transaction : transactions) {
            sendTransaction(transaction);
        }
        log.info("Batch of {} transactions submitted", transactions.size());
    }
    
    private Transaction convertV2ToV1(TransactionV2 v2) {
        Transaction v1 = new Transaction();
        v1.setTransactionId(v2.getTransactionId());
        v1.setCustomerId(v2.getCustomerId());
        v1.setFromAccount(v2.getFromAccount());
        v1.setToAccount(v2.getToAccount());
        v1.setAmount(v2.getAmount());
        v1.setCurrency(v2.getCurrency());
        v1.setType(v2.getType());
        v1.setStatus(v2.getStatus());
        v1.setTimestamp(v2.getTimestamp());
        v1.setDescription(v2.getDescription());
        
        // Map new V2 fields to metadata
        if (v1.getMetadata() == null) {
            v1.setMetadata(new HashMap<>());
        }
        v1.getMetadata().put("priority", v2.getPriority());
        v1.getMetadata().put("riskScore", v2.getRiskScore());
        v1.setCategory(v2.getCategory());
        
        return v1;
    }
}
