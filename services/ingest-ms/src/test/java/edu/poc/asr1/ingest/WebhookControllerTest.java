package edu.poc.asr1.ingest;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

@WebMvcTest(WebhookController.class)
@Import(SignatureVerifier.class)
@TestPropertySource(properties = "ingest.hmac-secret=test-secret")
class WebhookControllerTest {

    private static final String BODY = """
            {"eventId":"evt-1","type":"deposit.settled","occurredAt":"2026-12-01T13:00:00Z",
             "accountId":"acc_1","amount":{"value":1250.75,"currency":"USD"}}""";

    @Autowired MockMvc mvc;
    @Autowired SignatureVerifier verifier;
    @MockBean EventPublisher publisher;

    private MockHttpServletRequestBuilder req(String source, String body, String eventId, String signature) {
        var b = post("/webhooks/" + source).contentType(MediaType.APPLICATION_JSON)
                .content(body.getBytes(StandardCharsets.UTF_8));
        if (eventId != null) b.header("X-Event-Id", eventId);
        if (signature != null) b.header("X-Signature", signature);
        return b;
    }

    private String sig(String body) {
        return "sha256=" + verifier.sign(body.getBytes(StandardCharsets.UTF_8));
    }

    @Test
    void acepta202SoloTrasPersistirYEnviaLosAtributos() throws Exception {
        doNothing().when(publisher).publish(any());
        mvc.perform(req("argyle", BODY, "evt-1", sig(BODY))).andExpect(status().isAccepted());

        var captor = ArgumentCaptor.forClass(EventPublisher.WebhookMessage.class);
        verify(publisher).publish(captor.capture());
        var m = captor.getValue();
        org.junit.jupiter.api.Assertions.assertEquals("evt-1", m.eventId());
        org.junit.jupiter.api.Assertions.assertEquals("argyle", m.source());
        org.junit.jupiter.api.Assertions.assertEquals("deposit.settled", m.type());
        org.junit.jupiter.api.Assertions.assertNotNull(m.receivedAt());
    }

    @Test
    void responde503ySinReintentoImplicitoSiSqsNoConfirma() throws Exception {
        doThrow(new EventPublisher.PublishFailedException("timeout", new RuntimeException()))
                .when(publisher).publish(any());
        mvc.perform(req("central-payments", BODY, "evt-1", sig(BODY)))
                .andExpect(status().isServiceUnavailable())
                .andExpect(header().string("Retry-After", "5"));
    }

    @Test
    void firmaInvalidaDa401YNoPersiste() throws Exception {
        mvc.perform(req("argyle", BODY, "evt-1", "sha256=deadbeef")).andExpect(status().isUnauthorized());
        mvc.perform(req("argyle", BODY, "evt-1", null)).andExpect(status().isUnauthorized());
        verify(publisher, never()).publish(any());
    }

    @Test
    void jsonInvalidoDa400() throws Exception {
        String bad = "{no es json";
        mvc.perform(req("argyle", bad, "evt-1", sig(bad))).andExpect(status().isBadRequest());
        verify(publisher, never()).publish(any());
    }

    @Test
    void campoObligatorioAusenteDa400() throws Exception {
        String body = "{\"eventId\":\"evt-1\",\"type\":\"x\"}";
        mvc.perform(req("argyle", body, "evt-1", sig(body))).andExpect(status().isBadRequest());
        verify(publisher, never()).publish(any());
    }

    @Test
    void eventIdDelHeaderDistintoDelCuerpoDa400() throws Exception {
        mvc.perform(req("argyle", BODY, "otro", sig(BODY))).andExpect(status().isBadRequest());
        verify(publisher, never()).publish(any());
    }

    @Test
    void sourceDesconocidoDa404() throws Exception {
        mvc.perform(req("desconocido", BODY, "evt-1", sig(BODY))).andExpect(status().isNotFound());
    }
}
