package com.center.security;

/** Thông tin người dùng lấy từ JWT. */
public record AuthUser(Long id, String email, String role) {}
