using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System;
using System.Collections.Generic;
using System.Reflection;

namespace Data2AI.Kafka.Observability
{
    public static class OpenTelemetryExtensions
    {
        public static IHostApplicationBuilder AddProductionObservability(
            this IHostApplicationBuilder builder,
            string serviceName,
            string serviceVersion = "1.0.0")
        {
            // Add OpenTelemetry logging
            builder.Logging.AddOpenTelemetry(options =>
            {
                options.IncludeFormattedMessage = true;
                options.IncludeScopes = true;
                options.ParseStateValues = true;
            });

            // Configure OpenTelemetry resource
            var resourceBuilder = ResourceBuilder.CreateDefault()
                .AddService(serviceName, serviceVersion)
                .AddAttributes(new Dictionary<string, object>
                {
                    ["deployment.environment"] = "openshift-sandbox",
                    ["service.instance.id"] = Environment.MachineName,
                    ["telemetry.sdk.name"] = "opentelemetry",
                    ["telemetry.sdk.language"] = "dotnet",
                    ["telemetry.sdk.version"] = typeof(OpenTelemetry.Resources.Resource).Assembly.GetName().Version?.ToString() ?? "unknown"
                });

            // Configure tracing
            builder.Services.AddOpenTelemetry()
                .WithTracing(tracerProviderBuilder =>
                {
                    tracerProviderBuilder
                        .AddSource(serviceName)
                        .AddSource("Microsoft.AspNetCore")
                        .AddSource("Confluent.Kafka")
                        .AddHttpClientInstrumentation()
                        .AddAspNetCoreInstrumentation()
                        .AddSqlClientInstrumentation()
                        .SetResourceBuilder(resourceBuilder)
                        .AddAspNetCoreInstrumentation(options =>
                        {
                            options.RecordException = true;
                            options.EnrichWithHttpRequest = (activity, request) =>
                            {
                                activity.SetTag("http.request.method", request.Method);
                                activity.SetTag("http.request.scheme", request.Scheme);
                                activity.SetTag("http.request.host", request.Host.ToString());
                            };
                            options.EnrichWithHttpResponse = (activity, response) =>
                            {
                                activity.SetTag("http.response.status_code", response.StatusCode);
                            };
                        })
                        .AddOtlpExporter(options =>
                        {
                            options.Endpoint = new Uri("http://jaeger:4317");
                            options.Protocol = OtlpExportProtocol.Grpc;
                        })
                        .AddConsoleExporter();
                });

            // Configure metrics
            builder.Services.AddOpenTelemetry()
                .WithMetrics(meterProviderBuilder =>
                {
                    meterProviderBuilder
                        .AddMeter(serviceName)
                        .AddMeter("Microsoft.AspNetCore.Hosting")
                        .AddMeter("Confluent.Kafka")
                        .AddHttpClientInstrumentation()
                        .AddAspNetCoreInstrumentation()
                        .AddRuntimeInstrumentation()
                        .AddProcessInstrumentation()
                        .SetResourceBuilder(resourceBuilder)
                        .AddPrometheusExporter(options =>
                        {
                            options.ScrapeEndpointPath = "/metrics";
                            options.ScrapeResponseCacheDurationMilliseconds = 30000;
                        })
                        .AddOtlpExporter(options =>
                        {
                            options.Endpoint = new Uri("http://prometheus:9090/api/v1/write");
                        });
                });

            return builder;
        }

        public static IHostApplicationBuilder AddKafkaInstrumentation(
            this IHostApplicationBuilder builder)
        {
            // Add custom Kafka metrics
            builder.Services.AddSingleton<IKafkaMetrics, KafkaMetricsCollector>();

            // Add health checks for Kafka
            builder.Services.AddHealthChecks()
                .AddCheck<KafkaHealthCheck>("kafka");

            return builder;
        }
    }

    public interface IKafkaMetrics
    {
        void RecordMessageProduced(string topic, int messageSize);
        void RecordMessageConsumed(string topic, int messageSize, double lag);
        void RecordProducerError(string topic, string errorType);
        void RecordConsumerError(string topic, string errorType);
        void IncrementActiveConnections();
        void DecrementActiveConnections();
    }

    public class KafkaMetricsCollector : IKafkaMetrics
    {
        private readonly Counter<long> _messagesProduced;
        private readonly Counter<long> _messagesConsumed;
        private readonly Counter<long> _producerErrors;
        private readonly Counter<long> _consumerErrors;
        private readonly Histogram<double> _messageSize;
        private readonly Histogram<double> _consumerLag;
        private readonly ObservableGauge<int> _activeConnections;

        private int _currentConnections = 0;

        public KafkaMetricsCollector(IMeterFactory meterFactory)
        {
            var meter = meterFactory.Create("Data2AI.Kafka");

            _messagesProduced = meter.CreateCounter<long>(
                "kafka_messages_produced_total",
                description: "Total number of messages produced to Kafka");

            _messagesConsumed = meter.CreateCounter<long>(
                "kafka_messages_consumed_total",
                description: "Total number of messages consumed from Kafka");

            _producerErrors = meter.CreateCounter<long>(
                "kafka_producer_errors_total",
                description: "Total number of producer errors");

            _consumerErrors = meter.CreateCounter<long>(
                "kafka_consumer_errors_total",
                description: "Total number of consumer errors");

            _messageSize = meter.CreateHistogram<double>(
                "kafka_message_size_bytes",
                description: "Size of Kafka messages in bytes");

            _consumerLag = meter.CreateHistogram<double>(
                "kafka_consumer_lag_records",
                description: "Consumer lag in number of records");

            _activeConnections = meter.CreateObservableGauge<int>(
                "kafka_active_connections",
                description: "Number of active Kafka connections",
                observeValues: () => new Measurement<int>(_currentConnections));
        }

        public void RecordMessageProduced(string topic, int messageSize)
        {
            _messagesProduced.Add(1, new KeyValuePair<string, object>("topic", topic));
            _messageSize.Record(messageSize, new KeyValuePair<string, object>("topic", topic));
        }

        public void RecordMessageConsumed(string topic, int messageSize, double lag)
        {
            _messagesConsumed.Add(1, new KeyValuePair<string, object>("topic", topic));
            _messageSize.Record(messageSize, new KeyValuePair<string, object>("topic", topic));
            _consumerLag.Record(lag, new KeyValuePair<string, object>("topic", topic));
        }

        public void RecordProducerError(string topic, string errorType)
        {
            _producerErrors.Add(1, 
                new KeyValuePair<string, object>("topic", topic),
                new KeyValuePair<string, object>("error_type", errorType));
        }

        public void RecordConsumerError(string topic, string errorType)
        {
            _consumerErrors.Add(1,
                new KeyValuePair<string, object>("topic", topic),
                new KeyValuePair<string, object>("error_type", errorType));
        }

        public void IncrementActiveConnections()
        {
            System.Threading.Interlocked.Increment(ref _currentConnections);
        }

        public void DecrementActiveConnections()
        {
            System.Threading.Interlocked.Decrement(ref _currentConnections);
        }
    }

    using Microsoft.Extensions.Diagnostics.HealthChecks;

    public class KafkaHealthCheck : IHealthCheck
    {
        private readonly IProducer<string, string> _producer;

        public KafkaHealthCheck(IProducer<string, string> producer)
        {
            _producer = producer;
        }

        public async Task<HealthCheckResult> CheckHealthAsync(
            HealthCheckContext context,
            CancellationToken cancellationToken = default)
        {
            try
            {
                // Try to get metadata from Kafka cluster
                var metadata = _producer.GetMetadata(TimeSpan.FromSeconds(5));
                
                if (metadata.Brokers.Count > 0)
                {
                    return HealthCheckResult.Healthy(
                        $"Kafka cluster accessible. Brokers: {metadata.Brokers.Count}");
                }
                else
                {
                    return HealthCheckResult.Unhealthy("No brokers found in Kafka cluster");
                }
            }
            catch (Exception ex)
            {
                return HealthCheckResult.Unhealthy("Kafka cluster not accessible", ex);
            }
        }
    }
}
