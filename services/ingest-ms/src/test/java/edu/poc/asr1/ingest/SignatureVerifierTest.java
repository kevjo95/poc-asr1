package edu.poc.asr1.ingest;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class SignatureVerifierTest {
    private final SignatureVerifier v = new SignatureVerifier("secreto");
    private final byte[] body = "hola".getBytes(StandardCharsets.UTF_8);

    @Test
    void aceptaLaFirmaCorrectaEnMayusculasOMinusculas() {
        String hex = v.sign(body);
        assertTrue(v.isValid(body, "sha256=" + hex));
        assertTrue(v.isValid(body, "sha256=" + hex.toUpperCase()));
    }

    @Test
    void rechazaFirmaAlteradaCuerpoAlteradoOSinPrefijo() {
        String hex = v.sign(body);
        assertFalse(v.isValid(body, "sha256=" + hex.substring(1) + "0"));
        assertFalse(v.isValid("hola!".getBytes(StandardCharsets.UTF_8), "sha256=" + hex));
        assertFalse(v.isValid(body, hex));
        assertFalse(v.isValid(body, null));
    }

    @Test
    void conSecretoVacioNuncaValida() {
        assertFalse(new SignatureVerifier("").isValid(body, "sha256=" + v.sign(body)));
    }
}
