package com.center.controller;

import static com.center.Util.*;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** Học phí: lịch sử thu + công nợ. Chỉ ADMIN. */
@RestController
@RequestMapping("/api/payments")
public class PaymentController {
    private final JdbcTemplate db;

    public PaymentController(JdbcTemplate db) {
        this.db = db;
    }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(name = "enrollment_id", required = false) Long enrollmentId) {
        String sql = "select p.id, p.enrollment_id, p.amount, p.paid_at, p.method, p.note, "
                + "u.full_name as student_name, cl.name as class_name "
                + "from payments p join enrollments e on e.id = p.enrollment_id "
                + "join users u on u.id = e.student_id join classes cl on cl.id = e.class_id";
        List<Object> args = new ArrayList<>();
        if (enrollmentId != null) { sql += " where p.enrollment_id=?"; args.add(enrollmentId); }
        return db.queryForList(sql + " order by p.paid_at desc", args.toArray());
    }

    @GetMapping("/debts")
    public List<Map<String, Object>> debts() {
        return db.queryForList("""
                select e.id as enrollment_id, u.full_name as student_name, cl.name as class_name, co.fee,
                       coalesce(sum(p.amount), 0) as paid,
                       co.fee - coalesce(sum(p.amount), 0) as debt
                from enrollments e
                join users u on u.id = e.student_id
                join classes cl on cl.id = e.class_id
                join courses co on co.id = cl.course_id
                left join payments p on p.enrollment_id = e.id
                group by e.id, u.full_name, cl.name, co.fee
                order by debt desc, u.full_name
                """);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> b) {
        long eid = lng(b, "enrollment_id");
        BigDecimal amount = dec(b, "amount");
        if (amount.signum() <= 0)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Số tiền phải lớn hơn 0");
        BigDecimal debt = db.queryForObject("""
                select co.fee - coalesce((select sum(amount) from payments where enrollment_id = e.id), 0)
                from enrollments e
                join classes cl on cl.id = e.class_id
                join courses co on co.id = cl.course_id
                where e.id = ?
                """, BigDecimal.class, eid);
        if (debt != null && amount.compareTo(debt) > 0)
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Số tiền vượt quá công nợ còn lại");
        // paid_at (yyyy-MM-dd, không bắt buộc): ghi lại phiếu thu của ngày trước; bỏ trống = thời điểm hiện tại
        String paidAt = str(b, "paid_at");
        if (paidAt != null && java.time.LocalDate.parse(paidAt).isAfter(java.time.LocalDate.now()))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Ngày thu không được ở tương lai");
        return db.queryForMap("insert into payments(enrollment_id, amount, method, note, paid_at) "
                        + "values(?,?,?,?, coalesce(cast(? as date) + time '09:00', now())) returning *",
                eid, amount, strOr(b, "method", "CASH"), str(b, "note"), paidAt);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable long id) {
        db.update("delete from payments where id=?", id);
    }
}
