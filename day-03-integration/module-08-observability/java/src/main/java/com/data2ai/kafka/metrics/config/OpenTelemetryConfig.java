package com.data2ai.kafka.metrics.config;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.Meter;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.context.Scope;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.metrics.SdkMeterProvider;
import io.opentelemetry.sdk.metrics.exporter.PrometheusHttpServerExporter;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.semconv.ResourceAttributes;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.annotation.PostConstruct;
import javax.annotation.PreDestroy;
import java.io.IOException;
import java.util.concurrent.TimeUnit;

@Configuration
public class OpenTelemetryConfig {

    @Value("${spring.application.name:ebanking-metrics-java}")
    private String applicationName;

    @Value("${otel.prometheus.port:9464}")
    private int prometheusPort;

    private PrometheusHttpServerExporter prometheusExporter;
    private OpenTelemetry openTelemetry;

    @PostConstruct
    public void initializeOpenTelemetry() {
        // Create resource with service information
        Resource resource = Resource.getDefault()
                .toBuilder()
                .put(ResourceAttributes.SERVICE_NAME, applicationName)
                .put(ResourceAttributes.SERVICE_VERSION, "1.0.0")
                .put(ResourceAttributes.DEPLOYMENT_ENVIRONMENT, "openshift-sandbox")
                .build();

        // Initialize OpenTelemetry SDK
        openTelemetry = OpenTelemetrySdk.builder()
                .setTracerProvider(
                        SdkTracerProvider.builder()
                                .addSpanProcessor(SimpleSpanProcessor.create(
                                        io.opentelemetry.sdk.trace.export.BatchSpanProcessor.builder(
                                                io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter.builder()
                                                        .setEndpoint("http://jaeger:14250")
                                                        .build()
                                        )
                                                .setScheduleDelay(100, TimeUnit.MILLISECONDS)
                                                .build()
                                ))
                                .setResource(resource)
                                .build()
                )
                .setMeterProvider(
                        SdkMeterProvider.builder()
                                .registerMetricReader(
                                        PrometheusHttpServerExporter.builder()
                                                .setPort(prometheusPort)
                                                .build()
                                )
                                .setResource(resource)
                                .build()
                )
                .build();

        // Start Prometheus exporter
        prometheusExporter = PrometheusHttpServerExporter.builder()
                .setPort(prometheusPort)
                .build();
    }

    @PreDestroy
    public void shutdownOpenTelemetry() {
        if (prometheusExporter != null) {
            prometheusExporter.stop();
        }
        if (openTelemetry != null) {
            openTelemetry.close();
        }
    }

    @Bean
    public OpenTelemetry openTelemetry() {
        return openTelemetry;
    }

    @Bean
    public Tracer tracer() {
        return openTelemetry.getTracer("com.data2ai.kafka.metrics", "1.0.0");
    }

    @Bean
    public Meter meter() {
        return openTelemetry.getMeter("com.data2ai.kafka.metrics", "1.0.0");
    }
}
