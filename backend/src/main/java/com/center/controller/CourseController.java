package com.center.controller;

import static com.center.Util.*;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/courses")
public class CourseController {
    private final JdbcTemplate db;

    public CourseController(JdbcTemplate db) {
        this.db = db;
    }

    @GetMapping
    public List<Map<String, Object>> list() {
        return db.queryForList("select * from courses order by id desc");
    }

    @GetMapping("/{id}")
    public Map<String, Object> one(@PathVariable long id) {
        return db.queryForMap("select * from courses where id=?", id);
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> b) {
        return db.queryForMap("insert into courses(name,level,duration_weeks,fee,description) "
                        + "values(?,?,?,?,?) returning *",
                str(b, "name"), str(b, "level"), intOr(b, "duration_weeks", 0), fee(b), str(b, "description"));
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@PathVariable long id, @RequestBody Map<String, Object> b) {
        db.update("update courses set name=?, level=?, duration_weeks=?, fee=?, description=? where id=?",
                str(b, "name"), str(b, "level"), intOr(b, "duration_weeks", 0), fee(b), str(b, "description"), id);
        return one(id);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable long id) {
        db.update("delete from courses where id=?", id);
    }

    private BigDecimal fee(Map<String, Object> b) {
        return str(b, "fee") == null ? BigDecimal.ZERO : dec(b, "fee");
    }
}
