package edu.poc.asr1.ingest;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.net.URI;
import java.time.Duration;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.client.config.ClientOverrideConfiguration;
import software.amazon.awssdk.http.apache.ApacheHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.MessageAttributeValue;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

/** Un SendMessage por webhook (regla 3), sin lotes y con timeouts explícitos (regla 6). */
@Component
public class SqsEventPublisher implements EventPublisher {
    private static final Logger log = LoggerFactory.getLogger(SqsEventPublisher.class);

    private final SqsClient sqs;
    private final String queueUrl;
    private final Timer latency;

    public SqsEventPublisher(
            MeterRegistry registry,
            @Value("${ingest.queue-url}") String queueUrl,
            @Value("${ingest.sqs.region}") String region,
            @Value("${ingest.sqs.endpoint}") String endpoint,
            @Value("${ingest.sqs.timeout-ms}") long timeoutMs,
            @Value("${ingest.sqs.max-concurrency}") int maxConcurrency) {
        this.queueUrl = queueUrl;
        this.latency = Timer.builder("ingest.sqs.send.latency")
                .description("Latencia del SendMessage a SQS")
                .publishPercentileHistogram()
                .register(registry);
        var builder = SqsClient.builder()
                .region(Region.of(region))
                .httpClientBuilder(ApacheHttpClient.builder()
                        .maxConnections(maxConcurrency)
                        .connectionTimeout(Duration.ofMillis(timeoutMs))
                        .socketTimeout(Duration.ofMillis(timeoutMs)))
                .overrideConfiguration(ClientOverrideConfiguration.builder()
                        .apiCallTimeout(Duration.ofMillis(timeoutMs))
                        .apiCallAttemptTimeout(Duration.ofMillis(timeoutMs))
                        .build());
        if (endpoint != null && !endpoint.isBlank()) {
            builder.endpointOverride(URI.create(endpoint));
        }
        this.sqs = builder.build();
    }

    @Override
    public void publish(WebhookMessage m) throws PublishFailedException {
        long start = System.nanoTime();
        try {
            sqs.sendMessage(SendMessageRequest.builder()
                    .queueUrl(queueUrl)
                    .messageBody(m.body())
                    .messageAttributes(Map.of(
                            "eventId", attr(m.eventId()),
                            "source", attr(m.source()),
                            "type", attr(m.type()),
                            "receivedAt", attr(m.receivedAt())))
                    .build());
        } catch (RuntimeException e) {
            throw new PublishFailedException("SQS no confirmó el envío", e);
        } finally {
            long nanos = System.nanoTime() - start;
            latency.record(Duration.ofNanos(nanos));
            log.info("sqs.send eventId={} latencyMs={}", m.eventId(), nanos / 1_000_000);
        }
    }

    private static MessageAttributeValue attr(String v) {
        return MessageAttributeValue.builder().dataType("String").stringValue(v).build();
    }
}
