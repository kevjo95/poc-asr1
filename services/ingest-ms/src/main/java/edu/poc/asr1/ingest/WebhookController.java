package edu.poc.asr1.ingest;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

/**
 * POST /webhooks/{source}. Contrato de la PoC:
 * 202 solo después de que SQS confirmó; 400 JSON/campos inválidos; 401 firma inválida; 503 SQS no confirmó.
 * Sin estado: ninguna caché, sesión ni archivo (regla 2).
 */
@RestController
public class WebhookController {
    private static final Logger log = LoggerFactory.getLogger(WebhookController.class);
    private static final Set<String> SOURCES = Set.of("central-payments", "argyle");
    private static final List<String> REQUIRED = List.of("eventId", "type", "occurredAt", "accountId", "amount");

    private final SignatureVerifier verifier;
    private final EventPublisher publisher;
    private final ObjectMapper mapper;

    public WebhookController(SignatureVerifier verifier, EventPublisher publisher, ObjectMapper mapper) {
        this.verifier = verifier;
        this.publisher = publisher;
        this.mapper = mapper;
    }

    @PostMapping("/webhooks/{source}")
    public ResponseEntity<Map<String, String>> receive(
            @PathVariable String source,
            @RequestHeader(value = "X-Signature", required = false) String signature,
            @RequestHeader(value = "X-Event-Id", required = false) String eventIdHeader,
            @RequestBody byte[] body) {

        if (!SOURCES.contains(source)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of("error", "source desconocido"));
        }
        if (!verifier.isValid(body, signature)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "firma inválida"));
        }

        JsonNode json;
        try {
            json = mapper.readTree(body);
        } catch (IOException e) {
            return bad("JSON inválido");
        }
        if (json == null || !json.isObject()) {
            return bad("el cuerpo debe ser un objeto JSON");
        }
        for (String field : REQUIRED) {
            if (!json.hasNonNull(field)) {
                return bad("falta el campo obligatorio: " + field);
            }
        }
        String eventId = json.get("eventId").asText();
        if (eventIdHeader == null || !eventIdHeader.equals(eventId)) {
            return bad("X-Event-Id ausente o distinto de eventId");
        }

        var message = new EventPublisher.WebhookMessage(
                eventId, source, json.get("type").asText(), Instant.now().toString(),
                new String(body, java.nio.charset.StandardCharsets.UTF_8));
        try {
            publisher.publish(message);          // bloquea hasta que SQS confirma
        } catch (EventPublisher.PublishFailedException e) {
            log.warn("503 eventId={} causa={}", eventId, e.getCause() == null ? e.getMessage() : e.getCause().toString());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .header(HttpHeaders.RETRY_AFTER, "5")
                    .body(Map.of("error", "no se pudo persistir; reintente"));
        }
        return ResponseEntity.status(HttpStatus.ACCEPTED).body(Map.of("eventId", eventId));
    }

    private static ResponseEntity<Map<String, String>> bad(String msg) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", msg));
    }
}
