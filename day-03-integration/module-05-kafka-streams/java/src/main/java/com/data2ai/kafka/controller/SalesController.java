package com.data2ai.kafka.controller;

import com.data2ai.kafka.model.Sale;
import com.data2ai.kafka.model.SaleAggregate;
import com.data2ai.kafka.streams.SalesTopology;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StoreQueryParameters;
import org.apache.kafka.streams.state.QueryableStoreTypes;
import org.apache.kafka.streams.state.ReadOnlyKeyValueStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.kafka.config.StreamsBuilderFactoryBean;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1")
public class SalesController {

    private final KafkaTemplate<String, String> kafkaTemplate;
    private final StreamsBuilderFactoryBean factoryBean;
    private final ObjectMapper objectMapper;

    @Value("${INPUT_TOPIC:sales-events}")
    private String inputTopic;

    public SalesController(KafkaTemplate<String, String> kafkaTemplate,
                          StreamsBuilderFactoryBean factoryBean,
                          ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.factoryBean = factoryBean;
        this.objectMapper = objectMapper;
    }

    @PostMapping("/sales")
    public ResponseEntity<?> createSale(@RequestBody Sale sale) {
        try {
            String key = sale.getProductId();
            String value = objectMapper.writeValueAsString(sale);
            
            kafkaTemplate.send(inputTopic, key, value);
            
            return ResponseEntity.ok(Map.of(
                "status", "ACCEPTED",
                "productId", sale.getProductId(),
                "totalAmount", sale.getTotalAmount(),
                "topic", inputTopic
            ));
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of(
                "status", "ERROR",
                "error", e.getMessage()
            ));
        }
    }

    @GetMapping("/stats/by-product")
    public ResponseEntity<?> getStatsByProduct() {
        try {
            KafkaStreams streams = factoryBean.getKafkaStreams();
            if (streams == null || streams.state() != KafkaStreams.State.RUNNING) {
                return ResponseEntity.status(503).body(Map.of(
                    "error", "Streams not ready",
                    "state", streams != null ? streams.state().toString() : "NULL"
                ));
            }

            ReadOnlyKeyValueStore<String, SaleAggregate> store = streams.store(
                StoreQueryParameters.fromNameAndType(
                    SalesTopology.SALES_BY_PRODUCT_STORE,
                    QueryableStoreTypes.keyValueStore()
                )
            );

            Map<String, Object> result = new HashMap<>();
            store.all().forEachRemaining(kv -> {
                result.put(kv.key, Map.of(
                    "count", kv.value.getCount(),
                    "totalAmount", kv.value.getTotalAmount(),
                    "totalQuantity", kv.value.getTotalQuantity()
                ));
            });

            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }

    @GetMapping("/stats/per-minute")
    public ResponseEntity<?> getStatsPerMinute() {
        try {
            KafkaStreams streams = factoryBean.getKafkaStreams();
            if (streams == null || streams.state() != KafkaStreams.State.RUNNING) {
                return ResponseEntity.status(503).body(Map.of("error", "Streams not ready"));
            }

            return ResponseEntity.ok(Map.of(
                "message", "Check sales-per-minute topic in Kafka UI",
                "streamsState", streams.state().toString()
            ));
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/stores/{storeName}/all")
    public ResponseEntity<?> getAllFromStore(@PathVariable String storeName) {
        try {
            KafkaStreams streams = factoryBean.getKafkaStreams();
            if (streams == null || streams.state() != KafkaStreams.State.RUNNING) {
                return ResponseEntity.status(503).body(Map.of("error", "Streams not ready"));
            }

            ReadOnlyKeyValueStore<String, SaleAggregate> store = streams.store(
                StoreQueryParameters.fromNameAndType(storeName, QueryableStoreTypes.keyValueStore())
            );

            Map<String, Object> result = new HashMap<>();
            store.all().forEachRemaining(kv -> result.put(kv.key, kv.value));
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/stores/{storeName}/{key}")
    public ResponseEntity<?> getFromStore(@PathVariable String storeName, @PathVariable String key) {
        try {
            KafkaStreams streams = factoryBean.getKafkaStreams();
            if (streams == null || streams.state() != KafkaStreams.State.RUNNING) {
                return ResponseEntity.status(503).body(Map.of("error", "Streams not ready"));
            }

            ReadOnlyKeyValueStore<String, SaleAggregate> store = streams.store(
                StoreQueryParameters.fromNameAndType(storeName, QueryableStoreTypes.keyValueStore())
            );

            SaleAggregate value = store.get(key);
            if (value == null) {
                return ResponseEntity.notFound().build();
            }
            return ResponseEntity.ok(value);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().body(Map.of("error", e.getMessage()));
        }
    }

    @GetMapping("/health")
    public ResponseEntity<?> health() {
        KafkaStreams streams = factoryBean.getKafkaStreams();
        String state = streams != null ? streams.state().toString() : "NOT_INITIALIZED";
        return ResponseEntity.ok(Map.of(
            "status", "UP",
            "streamsState", state
        ));
    }
}
