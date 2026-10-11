package com.center;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

@SpringBootApplication
public class CenterApplication {

    public static void main(String[] args) {
        SpringApplication.run(CenterApplication.class, args);
    }

    /** Tạo tài khoản admin đầu tiên nếu chưa có. */
    @Bean
    CommandLineRunner seedAdmin(JdbcTemplate db, PasswordEncoder enc,
                                @Value("${app.admin-email}") String email,
                                @Value("${app.admin-password}") String password) {
        return args -> {
            Integer n = db.queryForObject("select count(*) from users where role='ADMIN'", Integer.class);
            if (n != null && n == 0) {
                db.update("insert into users(email,password_hash,full_name,role) values(?,?,?,'ADMIN')",
                        email, enc.encode(password), "Quản trị viên");
                System.out.println(">>> Đã tạo admin: " + email);
            }
        };
    }
}
