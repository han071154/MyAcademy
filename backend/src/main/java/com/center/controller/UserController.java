package com.center.controller;

import static com.center.Util.str;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;

/** Quản lý học viên + giáo viên (phân biệt bằng cột role). Chỉ ADMIN. */
@RestController
@RequestMapping("/api/users")
public class UserController {
    private static final String COLS = "id,email,full_name,role,phone,dob,address,active";
    private final JdbcTemplate db;
    private final PasswordEncoder enc;

    public UserController(JdbcTemplate db, PasswordEncoder enc) {
        this.db = db;
        this.enc = enc;
    }

    @GetMapping
    public List<Map<String, Object>> list(@RequestParam(required = false) String role,
                                          @RequestParam(required = false) String q) {
        StringBuilder sql = new StringBuilder("select " + COLS + " from users where 1=1");
        List<Object> args = new ArrayList<>();
        if (role != null && !role.isBlank()) { sql.append(" and role=?"); args.add(role); }
        if (q != null && !q.isBlank()) {
            sql.append(" and (lower(full_name) like ? or lower(email) like ? or coalesce(phone,'') like ?)");
            String k = "%" + q.trim().toLowerCase() + "%";
            args.add(k); args.add(k); args.add("%" + q.trim() + "%");
        }
        sql.append(" order by id desc");
        return db.queryForList(sql.toString(), args.toArray());
    }

    @PostMapping
    public Map<String, Object> create(@RequestBody Map<String, Object> b) {
        String pass = str(b, "password");
        if (pass == null) pass = "123456";
        return db.queryForMap("insert into users(email,password_hash,full_name,role,phone,dob,address) "
                        + "values(?,?,?,?,?,cast(? as date),?) returning " + COLS,
                str(b, "email"), enc.encode(pass), str(b, "full_name"), str(b, "role"),
                str(b, "phone"), str(b, "dob"), str(b, "address"));
    }

    @PutMapping("/{id}")
    public Map<String, Object> update(@PathVariable long id, @RequestBody Map<String, Object> b) {
        boolean active = b.get("active") == null || Boolean.parseBoolean(b.get("active").toString());
        db.update("update users set email=?, full_name=?, phone=?, dob=cast(? as date), address=?, active=? where id=?",
                str(b, "email"), str(b, "full_name"), str(b, "phone"), str(b, "dob"), str(b, "address"), active, id);
        String pass = str(b, "password");
        if (pass != null) db.update("update users set password_hash=? where id=?", enc.encode(pass), id);
        return db.queryForMap("select " + COLS + " from users where id=?", id);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable long id) {
        db.update("delete from users where id=? and role<>'ADMIN'", id);
    }
}
