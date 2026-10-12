package com.center.controller;

import static com.center.Util.*;

import com.center.security.AuthUser;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

/** Lớp học, ghi danh và điểm danh. */
@RestController
@RequestMapping("/api")
public class ClassController {
    private static final String LIST = """
            select cl.id, cl.course_id, co.name as course_name, co.fee,
                   cl.teacher_id, t.full_name as teacher_name,
                   cl.name, cl.start_date, cl.end_date, cl.schedule, cl.room, cl.max_students, cl.status,
                   (select count(*) from enrollments e where e.class_id = cl.id) as enrolled
            from classes cl
            join courses co on co.id = cl.course_id
            left join users t on t.id = cl.teacher_id
            """;
    private final JdbcTemplate db;

    public ClassController(JdbcTemplate db) {
        this.db = db;
    }

    // ---------- Lớp học ----------
    @GetMapping("/classes")
    public List<Map<String, Object>> list() {
        return db.queryForList(LIST + " order by cl.id desc");
    }

    @GetMapping("/classes/{id}")
    public Map<String, Object> one(@PathVariable long id) {
        return db.queryForMap(LIST + " where cl.id=?", id);
    }

    @PostMapping("/classes")
    public Map<String, Object> create(@RequestBody Map<String, Object> b) {
        Long id = db.queryForObject("insert into classes(course_id,teacher_id,name,start_date,end_date,schedule,room,"
                        + "max_students,status) values(?,?,?,cast(? as date),cast(? as date),?,?,?,?) returning id",
                Long.class, lng(b, "course_id"), lngOrNull(b, "teacher_id"), str(b, "name"), str(b, "start_date"),
                str(b, "end_date"), str(b, "schedule"), str(b, "room"), intOr(b, "max_students", 20),
                strOr(b, "status", "OPEN"));
        return one(id);
    }

    @PutMapping("/classes/{id}")
    public Map<String, Object> update(@PathVariable long id, @RequestBody Map<String, Object> b) {
        db.update("update classes set course_id=?, teacher_id=?, name=?, start_date=cast(? as date), "
                        + "end_date=cast(? as date), schedule=?, room=?, max_students=?, status=? where id=?",
                lng(b, "course_id"), lngOrNull(b, "teacher_id"), str(b, "name"), str(b, "start_date"),
                str(b, "end_date"), str(b, "schedule"), str(b, "room"), intOr(b, "max_students", 20),
                strOr(b, "status", "OPEN"), id);
        return one(id);
    }

    @DeleteMapping("/classes/{id}")
    public void delete(@PathVariable long id) {
        db.update("delete from classes where id=?", id);
    }

    /** Lớp của tôi: giáo viên → lớp mình dạy; học viên → lớp mình học. */
    @GetMapping("/my/classes")
    public List<Map<String, Object>> mine(@AuthenticationPrincipal AuthUser me) {
        return switch (me.role()) {
            case "TEACHER" -> db.queryForList(LIST + " where cl.teacher_id=? order by cl.start_date desc nulls last", me.id());
            // kèm số tiền học viên đã đóng cho từng lớp để hiện công nợ trên Trang chủ
            case "STUDENT" -> db.queryForList("select x.*, (select coalesce(sum(p.amount), 0) from payments p "
                    + "join enrollments e on e.id = p.enrollment_id where e.class_id = x.id and e.student_id = ?) as paid "
                    + "from (" + LIST + " where cl.id in (select class_id from enrollments where student_id=?)) x "
                    + "order by x.start_date desc nulls last", me.id(), me.id());
            default -> list();
        };
    }

    // ---------- Ghi danh ----------
    @GetMapping("/classes/{id}/students")
    public List<Map<String, Object>> students(@PathVariable long id, @AuthenticationPrincipal AuthUser me) {
        checkTeacher(me, id);
        return db.queryForList("select e.id as enrollment_id, u.id as student_id, u.full_name, u.phone, u.email "
                + "from enrollments e join users u on u.id = e.student_id where e.class_id=? order by u.full_name", id);
    }

    /** Admin ghi danh hộ (student_id trong body); học viên tự đăng ký thì luôn dùng chính mình. */
    @Transactional
    @PostMapping("/classes/{id}/enroll")
    public Map<String, Object> enroll(@PathVariable long id, @RequestBody(required = false) Map<String, Object> b,
                                      @AuthenticationPrincipal AuthUser me) {
        boolean self = "STUDENT".equals(me.role());
        long studentId = self ? me.id() : lng(b == null ? Map.of() : b, "student_id");
        // Khóa dòng lớp học đến hết transaction để 2 người đăng ký cùng lúc không vượt sĩ số
        Map<String, Object> c = db.queryForMap("select max_students, status from classes where id=? for update", id);
        if (self && !"OPEN".equals(c.get("status")))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Lớp không còn nhận đăng ký");
        Integer dup = db.queryForObject("select count(*) from enrollments where class_id=? and student_id=?",
                Integer.class, id, studentId);
        if (dup != null && dup > 0)
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    self ? "Bạn đã đăng ký lớp này" : "Học viên đã có trong lớp này");
        Integer n = db.queryForObject("select count(*) from enrollments where class_id=?", Integer.class, id);
        if (n != null && n >= ((Number) c.get("max_students")).intValue())
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Lớp đã đủ học viên");
        return db.queryForMap("insert into enrollments(student_id,class_id) values(?,?) returning id, student_id, class_id",
                studentId, id);
    }

    @DeleteMapping("/enrollments/{id}")
    public void unenroll(@PathVariable long id) {
        db.update("delete from enrollments where id=?", id);
    }

    /** Học viên tự hủy đăng ký: chỉ khi lớp còn mở và chưa đóng tiền / chưa điểm danh. */
    @Transactional
    @DeleteMapping("/my/classes/{classId}")
    public void cancelMine(@PathVariable long classId, @AuthenticationPrincipal AuthUser me) {
        if (!"STUDENT".equals(me.role()))
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Chỉ học viên mới tự hủy đăng ký");
        List<Map<String, Object>> rows = db.queryForList("select e.id, cl.status, "
                + "exists(select 1 from payments p where p.enrollment_id = e.id) as paid, "
                + "exists(select 1 from attendances a where a.enrollment_id = e.id) as attended "
                + "from enrollments e join classes cl on cl.id = e.class_id "
                + "where e.class_id=? and e.student_id=? for update of e", classId, me.id());
        if (rows.isEmpty())
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Bạn chưa đăng ký lớp này");
        Map<String, Object> e = rows.get(0);
        if (!"OPEN".equals(e.get("status")))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Lớp đã bắt đầu, vui lòng liên hệ trung tâm để hủy");
        if ((Boolean) e.get("paid") || (Boolean) e.get("attended"))
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Bạn đã đóng học phí hoặc đã đi học, vui lòng liên hệ trung tâm để hủy");
        db.update("delete from enrollments where id=?", e.get("id"));
    }

    // ---------- Điểm danh ----------
    @GetMapping("/classes/{id}/attendance")
    public List<Map<String, Object>> attendance(@PathVariable long id, @RequestParam String date,
                                                @AuthenticationPrincipal AuthUser me) {
        checkTeacher(me, id);
        return db.queryForList("select e.id as enrollment_id, u.full_name, a.status, a.note from enrollments e "
                + "join users u on u.id = e.student_id "
                + "left join attendances a on a.enrollment_id = e.id and a.session_date = cast(? as date) "
                + "where e.class_id=? order by u.full_name", date, id);
    }

    @SuppressWarnings("unchecked")
    @PostMapping("/attendance")
    public Map<String, Object> mark(@RequestBody Map<String, Object> b, @AuthenticationPrincipal AuthUser me) {
        long classId = lng(b, "class_id");
        checkTeacher(me, classId);
        String date = str(b, "date");
        List<Map<String, Object>> records = (List<Map<String, Object>>) b.get("records");
        for (Map<String, Object> r : records) {
            db.update("insert into attendances(enrollment_id, session_date, status, note) "
                    + "select e.id, cast(? as date), cast(? as text), cast(? as text) "
                    + "from enrollments e where e.id=? and e.class_id=? "
                    + "on conflict (enrollment_id, session_date) do update "
                    + "set status = excluded.status, note = excluded.note",
                    date, str(r, "status"), str(r, "note"), lng(r, "enrollment_id"), classId);
        }
        return Map.of("saved", records.size());
    }

    /** Giáo viên chỉ được thao tác trên lớp mình phụ trách. */
    private void checkTeacher(AuthUser me, long classId) {
        if ("TEACHER".equals(me.role())) {
            Integer n = db.queryForObject("select count(*) from classes where id=? and teacher_id=?",
                    Integer.class, classId, me.id());
            if (n == null || n == 0)
                throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Bạn không phụ trách lớp này");
        }
    }
}
