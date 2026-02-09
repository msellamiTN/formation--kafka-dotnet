package com.data2ai.kafka.streams;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.common.serialization.Deserializer;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serializer;

public class JsonSerde<T> implements Serde<T> {
    
    private final Class<T> targetType;
    private final ObjectMapper objectMapper;

    public JsonSerde(Class<T> targetType, ObjectMapper objectMapper) {
        this.targetType = targetType;
        this.objectMapper = objectMapper;
    }

    @Override
    public Serializer<T> serializer() {
        return (topic, data) -> {
            try {
                return objectMapper.writeValueAsBytes(data);
            } catch (Exception e) {
                throw new RuntimeException("Error serializing " + targetType.getName(), e);
            }
        };
    }

    @Override
    public Deserializer<T> deserializer() {
        return (topic, data) -> {
            try {
                if (data == null) return null;
                return objectMapper.readValue(data, targetType);
            } catch (Exception e) {
                throw new RuntimeException("Error deserializing " + targetType.getName(), e);
            }
        };
    }
}
