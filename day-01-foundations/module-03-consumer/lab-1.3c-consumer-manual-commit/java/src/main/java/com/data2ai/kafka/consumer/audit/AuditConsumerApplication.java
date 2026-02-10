package com.data2ai.kafka.consumer.audit;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AuditConsumerApplication {

    public static void main(String[] args) {
        SpringApplication.run(AuditConsumerApplication.class, args);
    }
}
