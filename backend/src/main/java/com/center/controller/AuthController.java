package com.center.controller;

import com.center.security.AuthUser;
import com.center.security.JwtService;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final JdbcTemplate db;
    private final PasswordEncoder enc;
    private final JwtService jwt;

    public AuthController(JdbcTemplate db, PasswordEncoder enc, JwtService jwt) {
        this.db = db;
        this.enc = enc;
        this.jwt = jwt;
    }

    @PostMapping("/login")
    public Map<String, Object> login(@RequestBody Map<String, String> body) {
        var rows = db.queryForList(
                "select id,email,password_hash,full_name,role,active from users where lower(email)=lower(?)",
                body.get("email"));
        if (rows.isEmpty()) throw bad();
        var u = rows.get(0);
        if (!(Boolean) u.get("active")
                || !enc.matches(body.getOrDefault("password", ""), (String) u.get("password_hash"))) throw bad();

        String token = jwt.create(((Number) u.get("id")).longValue(), (String) u.get("email"), (String) u.get("role"));
        return Map.of("token", token, "user", Map.of(
                "id", u.get("id"), "email", u.get("email"),
                "full_name", u.get("full_name"), "role", u.get("role")));
    }

    @GetMapping("/me")
    public Map<String, Object> me(@AuthenticationPrincipal AuthUser me) {
        return db.queryForMap("select id,email,full_name,role,phone from users where id=?", me.id());
    }

    @PostMapping("/change-password")
    public Map<String, Object> changePassword(@AuthenticationPrincipal AuthUser me,
                                              @RequestBody Map<String, String> body) {
        String hash = db.queryForObject("select password_hash from users where id=?", String.class, me.id());
        String neu = body.getOrDefault("new_password", "");
        if (!enc.matches(body.getOrDefault("old_password", ""), hash))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Mật khẩu cũ không đúng");
        if (neu.length() < 6)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Mật khẩu mới tối thiểu 6 ký tự");
        db.update("update users set password_hash=? where id=?", enc.encode(neu), me.id());
        return Map.of("ok", true);
    }

    private ResponseStatusException bad() {
        return new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Sai email hoặc mật khẩu");
    }
}
