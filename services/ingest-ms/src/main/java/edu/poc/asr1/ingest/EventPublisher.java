package edu.poc.asr1.ingest;

/** Persiste un webhook de forma durable. Debe retornar solo cuando la cola confirmó. */
public interface EventPublisher {

    void publish(WebhookMessage message) throws PublishFailedException;

    record WebhookMessage(String eventId, String source, String type, String receivedAt, String body) {}

    class PublishFailedException extends Exception {
        public PublishFailedException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
