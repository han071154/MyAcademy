package com.center.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class JwtService {
    private final SecretKey key;
    private final long expireMs;

    public JwtService(@Value("${app.jwt-secret}") String secret,
                      @Value("${app.jwt-expire-hours}") long hours) {
        if (secret.getBytes(StandardCharsets.UTF_8).length < 32)
            throw new IllegalStateException("Chưa đặt biến môi trường JWT_SECRET (cần chuỗi bí mật ≥ 32 ký tự)");
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.expireMs = hours * 3_600_000L;
    }

    public String create(long id, String email, String role) {
        Date now = new Date();
        return Jwts.builder()
                .subject(email)
                .claim("uid", id)
                .claim("role", role)
                .issuedAt(now)
                .expiration(new Date(now.getTime() + expireMs))
                .signWith(key)
                .compact();
    }

    public AuthUser parse(String token) {
        Claims c = Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();
        return new AuthUser(((Number) c.get("uid")).longValue(), c.getSubject(), (String) c.get("role"));
    }
}
