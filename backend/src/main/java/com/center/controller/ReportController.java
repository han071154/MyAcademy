package com.center.controller;

import java.util.HashMap;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/reports")
public class ReportController {
    private final JdbcTemplate db;

    public ReportController(JdbcTemplate db) {
        this.db = db;
    }

    @GetMapping("/summary")
    public Map<String, Object> summary() {
        Map<String, Object> r = new HashMap<>(db.queryForMap("""
                select
                  (select count(*) from users where role = 'STUDENT' and active) as students,
                  (select count(*) from users where role = 'TEACHER' and active) as teachers,
                  (select count(*) from courses) as courses,
                  (select count(*) from classes where status in ('OPEN', 'ONGOING')) as active_classes,
                  (select coalesce(sum(amount), 0) from payments) as total_revenue,
                  (select coalesce(sum(amount), 0) from payments
                     where date_trunc('month', paid_at) = date_trunc('month', now())) as month_revenue,
                  (select coalesce(sum(co.fee), 0) from enrollments e
                     join classes cl on cl.id = e.class_id join courses co on co.id = cl.course_id)
                  - (select coalesce(sum(amount), 0) from payments) as total_debt
                """));
        r.put("monthly", db.queryForList("""
                select to_char(m, 'MM/YYYY') as month, coalesce(sum(p.amount), 0) as total
                from generate_series(date_trunc('month', now()) - interval '5 months',
                                     date_trunc('month', now()), interval '1 month') as m
                left join payments p on date_trunc('month', p.paid_at) = m
                group by m
                order by m desc
                """));
        return r;
    }
}
