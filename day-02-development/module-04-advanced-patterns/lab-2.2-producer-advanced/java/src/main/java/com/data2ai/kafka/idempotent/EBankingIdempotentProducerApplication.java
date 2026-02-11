package com.data2ai.kafka.idempotent;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class EBankingIdempotentProducerApplication {

    public static void main(String[] args) {
        SpringApplication.run(EBankingIdempotentProducerApplication.class, args);
    }
}
