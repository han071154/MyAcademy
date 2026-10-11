package com.center;

import java.math.BigDecimal;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

/** Hàm tiện ích đọc dữ liệu từ body JSON. */
public final class Util {
    private Util() {}

    public static String str(Map<String, Object> m, String k) {
        Object v = m.get(k);
        return v == null || v.toString().isBlank() ? null : v.toString().trim();
    }

    public static String strOr(Map<String, Object> m, String k, String def) {
        String s = str(m, k);
        return s == null ? def : s;
    }

    public static long lng(Map<String, Object> m, String k) {
        Long v = lngOrNull(m, k);
        if (v == null) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Thiếu trường " + k);
        return v;
    }

    public static Long lngOrNull(Map<String, Object> m, String k) {
        String s = str(m, k);
        return s == null ? null : new BigDecimal(s).longValue();
    }

    public static int intOr(Map<String, Object> m, String k, int def) {
        String s = str(m, k);
        return s == null ? def : new BigDecimal(s).intValue();
    }

    public static BigDecimal dec(Map<String, Object> m, String k) {
        String s = str(m, k);
        if (s == null) throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Thiếu trường " + k);
        return new BigDecimal(s);
    }
}
