package com.center;

import java.util.Map;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private ResponseEntity<Map<String, String>> body(HttpStatus s, String msg) {
        return ResponseEntity.status(s).body(Map.of("message", msg));
    }

    @ExceptionHandler(ResponseStatusException.class)
    ResponseEntity<Map<String, String>> status(ResponseStatusException e) {
        return ResponseEntity.status(e.getStatusCode())
                .body(Map.of("message", e.getReason() == null ? "Lỗi" : e.getReason()));
    }

    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<Map<String, String>> integrity(DataIntegrityViolationException e) {
        return body(HttpStatus.CONFLICT, "Dữ liệu không hợp lệ, bị trùng hoặc đang được sử dụng ở nơi khác");
    }

    @ExceptionHandler(EmptyResultDataAccessException.class)
    ResponseEntity<Map<String, String>> notFound(EmptyResultDataAccessException e) {
        return body(HttpStatus.NOT_FOUND, "Không tìm thấy dữ liệu");
    }

    @ExceptionHandler({NumberFormatException.class, HttpMessageNotReadableException.class,
            java.time.format.DateTimeParseException.class})
    ResponseEntity<Map<String, String>> bad(Exception e) {
        return body(HttpStatus.BAD_REQUEST, "Dữ liệu gửi lên không hợp lệ");
    }
}
