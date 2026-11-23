package edu.poc.asr1.ingest;

import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/** Valida X-Signature: "sha256=" + HMAC-SHA256 hex del cuerpo, con comparación en tiempo constante. */
@Component
public class SignatureVerifier {
    private static final String PREFIX = "sha256=";
    private final byte[] secret;

    public SignatureVerifier(@Value("${ingest.hmac-secret}") String secret) {
        this.secret = secret.getBytes(StandardCharsets.UTF_8);
    }

    public boolean isValid(byte[] body, String header) {
        if (secret.length == 0 || header == null || !header.startsWith(PREFIX)) {
            return false;
        }
        byte[] expected = sign(body).getBytes(StandardCharsets.UTF_8);
        byte[] given = header.substring(PREFIX.length()).toLowerCase().getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, given);
    }

    public String sign(byte[] body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            return HexFormat.of().formatHex(mac.doFinal(body));
        } catch (NoSuchAlgorithmException | InvalidKeyException e) {
            throw new IllegalStateException(e);
        }
    }
}
