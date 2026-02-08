package com.data2ai.kafka.streams;

import com.data2ai.kafka.model.Sale;
import com.data2ai.kafka.model.SaleAggregate;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.kstream.*;
import org.apache.kafka.streams.state.KeyValueStore;
import org.apache.kafka.streams.state.WindowStore;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.EnableKafkaStreams;

import java.time.Duration;

@Configuration
@EnableKafkaStreams
public class SalesTopology {

    @Value("${INPUT_TOPIC:sales-events}")
    private String inputTopic;

    @Value("${OUTPUT_TOPIC:sales-by-product}")
    private String outputTopic;

    @Value("${PRODUCTS_TOPIC:products}")
    private String productsTopic;

    private final ObjectMapper objectMapper = new ObjectMapper();

    public static final String SALES_BY_PRODUCT_STORE = "sales-by-product-store";
    public static final String SALES_PER_MINUTE_STORE = "sales-per-minute-store";

    @Bean
    public KStream<String, String> kStream(StreamsBuilder builder) {
        // Read sales events stream
        KStream<String, String> salesStream = builder.stream(inputTopic,
            Consumed.with(Serdes.String(), Serdes.String()));

        // 1. Filter large sales (> 100€) and send to large-sales topic
        salesStream
            .filter((key, value) -> {
                try {
                    Sale sale = objectMapper.readValue(value, Sale.class);
                    return sale.getTotalAmount() > 100;
                } catch (Exception e) {
                    return false;
                }
            })
            .to("large-sales", Produced.with(Serdes.String(), Serdes.String()));

        // 2. Aggregate sales by product
        salesStream
            .selectKey((key, value) -> {
                try {
                    Sale sale = objectMapper.readValue(value, Sale.class);
                    return sale.getProductId();
                } catch (Exception e) {
                    return "unknown";
                }
            })
            .groupByKey(Grouped.with(Serdes.String(), Serdes.String()))
            .aggregate(
                SaleAggregate::new,
                (key, value, aggregate) -> {
                    try {
                        Sale sale = objectMapper.readValue(value, Sale.class);
                        return aggregate.add(sale);
                    } catch (Exception e) {
                        return aggregate;
                    }
                },
                Materialized.<String, SaleAggregate, KeyValueStore<Bytes, byte[]>>as(SALES_BY_PRODUCT_STORE)
                    .withKeySerde(Serdes.String())
                    .withValueSerde(new JsonSerde<>(SaleAggregate.class, objectMapper))
            )
            .toStream()
            .mapValues(agg -> {
                try {
                    return objectMapper.writeValueAsString(agg);
                } catch (Exception e) {
                    return "{}";
                }
            })
            .to(outputTopic, Produced.with(Serdes.String(), Serdes.String()));

        // 3. Windowed aggregation - sales per minute
        salesStream
            .selectKey((key, value) -> "all-sales")
            .groupByKey(Grouped.with(Serdes.String(), Serdes.String()))
            .windowedBy(TimeWindows.ofSizeWithNoGrace(Duration.ofMinutes(1)))
            .aggregate(
                SaleAggregate::new,
                (key, value, aggregate) -> {
                    try {
                        Sale sale = objectMapper.readValue(value, Sale.class);
                        return aggregate.add(sale);
                    } catch (Exception e) {
                        return aggregate;
                    }
                },
                Materialized.<String, SaleAggregate, WindowStore<Bytes, byte[]>>as(SALES_PER_MINUTE_STORE)
                    .withKeySerde(Serdes.String())
                    .withValueSerde(new JsonSerde<>(SaleAggregate.class, objectMapper))
            )
            .toStream()
            .map((windowedKey, value) -> {
                String newKey = windowedKey.window().startTime() + "-" + windowedKey.window().endTime();
                try {
                    return KeyValue.pair(newKey, objectMapper.writeValueAsString(value));
                } catch (Exception e) {
                    return KeyValue.pair(newKey, "{}");
                }
            })
            .to("sales-per-minute", Produced.with(Serdes.String(), Serdes.String()));

        // 4. Join with products table for enrichment
        KTable<String, String> productsTable = builder.table(productsTopic,
            Consumed.with(Serdes.String(), Serdes.String()),
            Materialized.as("products-store"));

        salesStream
            .selectKey((key, value) -> {
                try {
                    Sale sale = objectMapper.readValue(value, Sale.class);
                    return sale.getProductId();
                } catch (Exception e) {
                    return "unknown";
                }
            })
            .join(productsTable, (saleJson, productJson) -> {
                try {
                    return "{\"sale\":" + saleJson + ",\"product\":" + productJson + "}";
                } catch (Exception e) {
                    return saleJson;
                }
            })
            .to("enriched-sales", Produced.with(Serdes.String(), Serdes.String()));

        return salesStream;
    }
}
