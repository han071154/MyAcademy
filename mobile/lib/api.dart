import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static final Api i = Api._();

  /// Đã đăng nhập (có phiên Supabase Auth + hồ sơ trong bảng users).
  final ValueNotifier<bool> loggedIn = ValueNotifier(false);

  /// Tài khoản đang dùng mật khẩu do admin cấp / mật khẩu mặc định → bắt đổi trước khi dùng app.
  final ValueNotifier<bool> mustChangePassword = ValueNotifier(false);
  final ValueNotifier<int> changes = ValueNotifier(0);

  Map<String, dynamic>? user;

  Api._();

  SupabaseClient get _sb => Supabase.instance.client;

  String get role => (user?['role'] ?? '') as String;
  int? get userId => user?['id'] != null ? int.tryParse(user!['id'].toString()) : null;

  static const _profileCols = 'id,email,full_name,role,phone,must_change_password';
  static const minPasswordLength = 8;

  /// Gọi 1 lần lúc mở app: khôi phục phiên đăng nhập do Supabase lưu sẵn.
  Future<void> load() async {
    _sb.auth.onAuthStateChange.listen((data) {
      // Phiên hết hạn / bị thu hồi → về màn hình đăng nhập.
      if (data.event == AuthChangeEvent.signedOut) _clearLocal();
    });

    if (_sb.auth.currentSession == null) return;
    final p = await SharedPreferences.getInstance();
    final cached = p.getString('user');
    try {
      await _loadProfile();
    } catch (_) {
      // Mất mạng lúc mở app: dùng tạm hồ sơ đã lưu, quyền vẫn do RLS phía server kiểm tra.
      if (cached != null && _sb.auth.currentSession != null) {
        try {
          _setUser(Map<String, dynamic>.from(jsonDecode(cached)));
        } catch (_) {}
      }
    }
  }

  Future<void> _loadProfile() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw ApiException('Phiên đăng nhập không hợp lệ');
    final row = await _sb.from('users').select(_profileCols).eq('auth_id', uid).eq('active', true).maybeSingle();
    if (row == null) {
      await _sb.auth.signOut();
      throw ApiException('Tài khoản đã bị khóa hoặc chưa được cấp quyền');
    }
    _setUser(Map<String, dynamic>.from(row));
    final p = await SharedPreferences.getInstance();
    await p.setString('user', jsonEncode(user));
  }

  void _setUser(Map<String, dynamic> u) {
    user = u;
    mustChangePassword.value = u['must_change_password'] == true;
    loggedIn.value = true;
  }

  Future<void> _clearLocal() async {
    user = null;
    mustChangePassword.value = false;
    loggedIn.value = false;
    final p = await SharedPreferences.getInstance();
    await p.remove('user');
    await p.remove('token');
  }

  String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login credentials')) return 'Sai email hoặc mật khẩu';
    if (m.contains('banned')) return 'Tài khoản đã bị khóa';
    if (m.contains('expired') || m.contains('otp') || m.contains('token')) {
      return 'Mã xác nhận không đúng hoặc đã hết hạn';
    }
    if (m.contains('rate limit') || m.contains('security purposes')) {
      return 'Bạn thao tác quá nhanh, vui lòng thử lại sau ít phút';
    }
    if (m.contains('should be different')) return 'Mật khẩu mới phải khác mật khẩu cũ';
    if (m.contains('password')) return 'Mật khẩu không hợp lệ (tối thiểu $minPasswordLength ký tự)';
    return e.message;
  }

  Future<T> _auth<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthException catch (e) {
      throw ApiException(_authMessage(e));
    } on PostgrestException catch (e) {
      throw ApiException(_dbMessage(e));
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void _checkNewPassword(String pw) {
    if (pw.length < minPasswordLength) {
      throw ApiException('Mật khẩu mới tối thiểu $minPasswordLength ký tự');
    }
  }

  Future<void> login(String email, String password) => _auth(() async {
        await _sb.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
        await _loadProfile();
      });

  /// Học viên tự đăng ký: server tạo tài khoản vai trò STUDENT, xong đăng nhập luôn.
  Future<void> registerStudent({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required DateTime dob,
    required String address,
  }) =>
      _auth(() async {
        _checkNewPassword(password);
        await _sb.rpc('register_student', params: {
          'p_email': email.trim().toLowerCase(),
          'p_password': password,
          'p_full_name': fullName.trim(),
          'p_phone': phone.trim(),
          'p_dob': dob.toIso8601String().substring(0, 10),
          'p_address': address.trim(),
        });
        await _sb.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
        await _loadProfile();
      });

  /// Tự cập nhật hồ sơ (họ tên, SĐT, ngày sinh, địa chỉ). Email và vai trò không đổi được.
  Future<void> updateMyProfile({
    required String fullName,
    required String phone,
    required DateTime dob,
    required String address,
  }) =>
      _auth(() async {
        await _sb.rpc('update_my_profile', params: {
          'p_full_name': fullName.trim(),
          'p_phone': phone.trim(),
          'p_dob': dob.toIso8601String().substring(0, 10),
          'p_address': address.trim(),
        });
        await _loadProfile(); // tên mới hiện ngay ở trang chủ
        changes.value++;
      });

  // ---------- Đóng học phí bằng chuyển khoản (database/payment_requests.sql) ----------

  /// Yêu cầu đóng tiền: học viên chỉ thấy của mình, admin thấy tất cả (RLS).
  Future<List> paymentRequests({String? status}) => _auth(() async {
        var q = _sb.from('v_payment_requests').select();
        if (status != null) q = q.eq('status', status);
        return await q.order('created_at', ascending: false) as List;
      });

  /// Học viên báo đã chuyển khoản cho lớp [classId]. Chờ admin xác nhận mới tính tiền.
  Future<void> createPaymentRequest(int classId, num amount) => _auth(() async {
        await _sb.rpc('create_payment_request', params: {'p_class_id': classId, 'p_amount': amount});
        changes.value++;
      });

  Future<void> cancelPaymentRequest(int id) => _auth(() async {
        await _sb.rpc('cancel_payment_request', params: {'p_id': id});
        changes.value++;
      });

  Future<void> confirmPaymentRequest(int id) => _auth(() async {
        await _sb.rpc('confirm_payment_request', params: {'p_id': id});
        changes.value++;
      });

  Future<void> rejectPaymentRequest(int id, String? reason) => _auth(() async {
        await _sb.rpc('reject_payment_request', params: {'p_id': id, 'p_reason': reason});
        changes.value++;
      });

  Future<void> logout() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
    await _clearLocal();
  }

  /// Đổi mật khẩu khi đang đăng nhập. [oldPassword] = null khi bị bắt đổi ở lần đăng nhập đầu.
  Future<void> changePassword(String? oldPassword, String newPassword) => _auth(() async {
        _checkNewPassword(newPassword);
        if (oldPassword != null) {
          try {
            await _sb.auth.signInWithPassword(email: user!['email'] as String, password: oldPassword);
          } on AuthException {
            throw ApiException('Mật khẩu hiện tại không đúng');
          }
        }
        await _sb.auth.updateUser(UserAttributes(password: newPassword));
        await _sb.rpc('password_changed');
        user?['must_change_password'] = false;
        mustChangePassword.value = false;
      });

  /// Quên mật khẩu bước 1: Supabase gửi mã xác nhận về email.
  Future<void> sendResetCode(String email) =>
      _auth(() => _sb.auth.resetPasswordForEmail(email.trim().toLowerCase()));

  /// Quên mật khẩu bước 2: nhập mã trong email + mật khẩu mới, xong thì đăng nhập luôn.
  Future<void> resetPasswordWithCode(String email, String code, String newPassword) => _auth(() async {
        _checkNewPassword(newPassword);
        await _sb.auth.verifyOTP(type: OtpType.recovery, email: email.trim().toLowerCase(), token: code.trim());
        await _sb.auth.updateUser(UserAttributes(password: newPassword));
        await _sb.rpc('password_changed');
        await _loadProfile();
      });

  Map<String, dynamic> _clean(dynamic data) {
    if (data is! Map) return {};
    final map = <String, dynamic>{};
    for (final e in data.entries) {
      final k = e.key.toString();
      final v = e.value;
      if (v is String && v.isEmpty) {
        map[k] = null;
      } else {
        map[k] = v;
      }
    }
    return map;
  }

  dynamic _unwrap(dynamic val) {
    if (val is String) {
      try {
        return jsonDecode(val);
      } catch (_) {
        return val;
      }
    }
    return val;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dispatchGet(path, query));

  Future<dynamic> post(String path, [dynamic data]) =>
      _changed(_wrap(() => _dispatchPost(path, data)));

  Future<dynamic> put(String path, [dynamic data]) =>
      _changed(_wrap(() => _dispatchPut(path, data)));

  Future<dynamic> delete(String path) =>
      _changed(_wrap(() => _dispatchDelete(path)));

  Future<dynamic> _changed(Future<dynamic> f) async {
    final r = await f;
    changes.value++;
    return r;
  }

  DateTime? _lastClassSync;

  /// Cập nhật trạng thái lớp theo ngày (Mở → Đang học → Kết thúc) trước khi hiện danh sách lớp.
  /// Tối đa 10 phút 1 lần; lỗi (vd chưa chạy SQL mới) thì bỏ qua, không chặn việc xem lớp.
  Future<void> _syncClassStatus() async {
    final now = DateTime.now();
    if (_lastClassSync != null && now.difference(_lastClassSync!) < const Duration(minutes: 10)) return;
    _lastClassSync = now;
    try {
      await _sb.rpc('sync_class_status');
    } catch (_) {}
  }

  /// Đổi lỗi kỹ thuật của database sang câu dễ hiểu.
  static String _dbMessage(PostgrestException e) {
    final m = e.message;
    if (m.contains('users_phone_format')) return 'Số điện thoại không hợp lệ (10 số, bắt đầu bằng 0)';
    if (m.contains('users_email_key') || m.contains('duplicate key') && m.contains('email')) {
      return 'Email đã được sử dụng';
    }
    return m;
  }

  Future<dynamic> _wrap(Future<dynamic> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      throw ApiException(_dbMessage(e));
    } catch (e) {
      throw ApiException(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<dynamic> _dispatchGet(String path, Map<String, dynamic>? query) async {
    // 1. /courses
    if (path == '/courses') {
      return await _sb.from('courses').select().order('id', ascending: false);
    }
    if (path.startsWith('/courses/')) {
      final id = int.parse(path.substring(9));
      return await _sb.from('courses').select().eq('id', id).single();
    }

    // 2. /classes
    if (path == '/classes') {
      await _syncClassStatus();
      return await _sb.from('v_classes').select().order('id', ascending: false);
    }
    if (path == '/my/classes') {
      await _syncClassStatus();
      final res = await _sb.rpc('get_my_classes');
      return _unwrap(res);
    }
    if (path.startsWith('/classes/') && path.endsWith('/students')) {
      final id = int.parse(path.split('/')[2]);
      return await _sb.from('v_enrollments').select().eq('class_id', id).order('full_name');
    }
    if (path.startsWith('/classes/') && path.endsWith('/attendance')) {
      final id = int.parse(path.split('/')[2]);
      final date = query?['date']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10);
      final res = await _sb.rpc('get_attendance', params: {
        'p_class_id': id,
        'p_date': date,
      });
      return _unwrap(res);
    }
    if (path.startsWith('/classes/') && path.endsWith('/my-attendance')) {
      final id = int.parse(path.split('/')[2]);
      final res = await _sb.rpc('get_student_attendance', params: {'p_class_id': id});
      return _unwrap(res);
    }
    if (path.startsWith('/classes/') && path.endsWith('/assignments')) {
      final id = int.parse(path.split('/')[2]);
      return await _sb.from('v_assignments').select().eq('class_id', id).order('id', ascending: false);
    }
    if (path.startsWith('/classes/')) {
      final id = int.parse(path.substring(9));
      return await _sb.from('v_classes').select().eq('id', id).single();
    }

    // 3. /assignments
    if (path.startsWith('/assignments/') && path.endsWith('/submissions')) {
      final id = int.parse(path.split('/')[2]);
      return await _sb.from('v_submissions').select().eq('assignment_id', id).order('submitted_at', ascending: false);
    }
    if (path == '/my/submissions') {
      return await _sb.from('submissions').select('id,assignment_id,score,submitted_at').eq('student_id', userId!);
    }
    if (path.startsWith('/assignments/') && path.endsWith('/my-submission')) {
      final id = int.parse(path.split('/')[2]);
      final rows = await _sb.from('submissions').select().eq('assignment_id', id).eq('student_id', userId!);
      return rows.isNotEmpty ? rows.first : null;
    }

    // 4. /users
    if (path == '/users') {
      var q = _sb.from('users').select('id,email,full_name,role,phone,dob,address,active');
      if (query != null) {
        final roleVal = query['role']?.toString();
        if (roleVal != null && roleVal.isNotEmpty) {
          q = q.eq('role', roleVal);
        }
        final qText = query['q']?.toString().trim();
        if (qText != null && qText.isNotEmpty) {
          q = q.or('full_name.ilike.%$qText%,email.ilike.%$qText%,phone.ilike.%$qText%');
        }
      }
      return await q.order('id', ascending: false);
    }

    // 5. /payments
    if (path == '/payments') {
      var q = _sb.from('v_payments').select();
      if (query != null && query['enrollment_id'] != null) {
        q = q.eq('enrollment_id', query['enrollment_id'] as Object);
      }
      return await q.order('paid_at', ascending: false);
    }
    if (path == '/payments/debts') {
      return await _sb.from('v_debts').select().order('debt', ascending: false);
    }

    // 6. /reports/summary
    if (path == '/reports/summary') {
      final res = await _sb.rpc('reports_summary');
      return _unwrap(res);
    }

    // 7. /auth/me
    if (path == '/auth/me') {
      return await _sb.from('users').select('id,email,full_name,role,phone,dob,address').eq('id', userId!).single();
    }

    throw ApiException('Đường dẫn không hợp lệ: $path');
  }

  Future<dynamic> _dispatchPost(String path, dynamic data) async {
    final b = _clean(data);

    // /courses
    if (path == '/courses') {
      return await _sb.from('courses').insert(b).select().single();
    }

    // /classes
    if (path == '/classes') {
      final inserted = await _sb.from('classes').insert(b).select('id').single();
      return await _sb.from('v_classes').select().eq('id', inserted['id']).single();
    }
    if (path.startsWith('/classes/') && path.endsWith('/enroll')) {
      final classId = int.parse(path.split('/')[2]);
      // Server tự xác định người đăng ký theo phiên đăng nhập; student_id chỉ dùng khi admin ghi danh hộ.
      final res = await _sb.rpc('enroll_student', params: {
        'p_class_id': classId,
        'p_student_id': b['student_id'] != null ? int.parse(b['student_id'].toString()) : null,
      });
      return _unwrap(res);
    }

    // /attendance
    if (path == '/attendance') {
      final res = await _sb.rpc('save_attendance', params: {
        'p_class_id': data['class_id'],
        'p_date': data['date'],
        'p_records': data['records'],
      });
      return _unwrap(res);
    }

    // /assignments
    if (path == '/assignments') {
      return await _sb.from('assignments').insert({
        ...b,
        'teacher_id': userId,
      }).select().single();
    }
    if (path.startsWith('/assignments/') && path.endsWith('/submit')) {
      final assignmentId = int.parse(path.split('/')[2]);
      return await _sb.from('submissions').upsert({
        ...b,
        'assignment_id': assignmentId,
        'student_id': userId,
        // Giờ nộp do server ghi (trigger submissions_guard), không lấy giờ điện thoại.
      }, onConflict: 'assignment_id,student_id').select().single();
    }

    // /payments
    if (path == '/payments') {
      final res = await _sb.rpc('create_payment', params: {
        'p_enrollment_id': b['enrollment_id'],
        'p_amount': b['amount'],
        'p_method': b['method'] ?? 'CASH',
        'p_note': b['note'],
      });
      return _unwrap(res);
    }

    // /users
    if (path == '/users') {
      final res = await _sb.rpc('create_user', params: {
        'p_email': b['email'],
        'p_full_name': b['full_name'],
        'p_role': b['role'],
        'p_password': b['password'],
        'p_phone': b['phone'],
        'p_dob': b['dob'],
        'p_address': b['address'],
      });
      return _unwrap(res);
    }

    // /auth/change-password
    if (path == '/auth/change-password') {
      await changePassword(b['old_password']?.toString() ?? '', b['new_password']?.toString() ?? '');
      return {'ok': true};
    }

    throw ApiException('Đường dẫn không hợp lệ: $path');
  }

  Future<dynamic> _dispatchPut(String path, dynamic data) async {
    final b = _clean(data);

    // /courses/{id}
    if (path.startsWith('/courses/')) {
      final id = int.parse(path.substring(9));
      return await _sb.from('courses').update(b).eq('id', id).select().single();
    }

    // /classes/{id}
    if (path.startsWith('/classes/')) {
      final id = int.parse(path.substring(9));
      await _sb.from('classes').update(b).eq('id', id);
      return await _sb.from('v_classes').select().eq('id', id).single();
    }

    // /assignments/{id}
    if (path.startsWith('/assignments/')) {
      final id = int.parse(path.substring(13));
      return await _sb.from('assignments').update(b).eq('id', id).select().single();
    }

    // /submissions/{id}/grade
    if (path.startsWith('/submissions/') && path.endsWith('/grade')) {
      final id = int.parse(path.split('/')[2]);
      return await _sb.from('submissions').update({
        'score': b['score'],
        'feedback': b['feedback'],
      }).eq('id', id).select().single();
    }

    // /users/{id}
    if (path.startsWith('/users/')) {
      final id = int.parse(path.substring(7));
      final res = await _sb.rpc('update_user', params: {
        'p_id': id,
        'p_email': b['email'],
        'p_full_name': b['full_name'],
        'p_phone': b['phone'],
        'p_dob': b['dob'],
        'p_address': b['address'],
        'p_active': b['active'] ?? true,
        'p_password': b['password'],
      });
      return _unwrap(res);
    }

    throw ApiException('Đường dẫn không hợp lệ: $path');
  }

  Future<dynamic> _dispatchDelete(String path) async {
    // /courses/{id}
    if (path.startsWith('/courses/')) {
      final id = int.parse(path.substring(9));
      await _sb.from('courses').delete().eq('id', id);
      return;
    }

    // /classes/{id}
    if (path.startsWith('/classes/')) {
      final id = int.parse(path.substring(9));
      await _sb.from('classes').delete().eq('id', id);
      return;
    }

    // /assignments/{id}
    if (path.startsWith('/assignments/')) {
      final id = int.parse(path.substring(13));
      await _sb.from('assignments').delete().eq('id', id);
      return;
    }

    // /enrollments/{id}
    if (path.startsWith('/enrollments/')) {
      final id = int.parse(path.substring(13));
      await _sb.from('enrollments').delete().eq('id', id);
      return;
    }

    // /my/classes/{classId}
    if (path.startsWith('/my/classes/')) {
      final classId = int.parse(path.substring(12));
      final res = await _sb.rpc('cancel_my_enrollment', params: {'p_class_id': classId});
      return _unwrap(res);
    }

    // /payments/{id}
    if (path.startsWith('/payments/')) {
      final id = int.parse(path.substring(10));
      await _sb.from('payments').delete().eq('id', id);
      return;
    }

    // /users/{id}
    if (path.startsWith('/users/')) {
      final id = int.parse(path.substring(7));
      return _unwrap(await _sb.rpc('delete_user', params: {'p_id': id}));
    }

    throw ApiException('Đường dẫn không hợp lệ: $path');
  }

  /// Upload tệp vào bucket private. Trả về "storage:<đường dẫn>" để lưu vào DB;
  /// khi hiển thị dùng [fileUrl] để lấy link tạm thời (signed URL).
  Future<String> uploadFile(String fileName, Uint8List bytes, {String? mimeType}) => _auth(() async {
        final uid = _sb.auth.currentUser?.id;
        if (uid == null) throw ApiException('Bạn cần đăng nhập lại');
        final cleanName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_$cleanName';
        await _sb.storage.from('submissions').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: _guessMime(fileName, fallback: mimeType)),
            );
        return '$storagePrefix$path';
      });

  static const storagePrefix = 'storage:';

  /// Link xem tệp: tệp trong bucket private → signed URL hết hạn sau 1 giờ.
  /// Dữ liệu cũ (http / data:) giữ nguyên.
  Future<String> fileUrl(String stored) async {
    if (!stored.startsWith(storagePrefix)) return stored;
    return _auth(() => _sb.storage.from('submissions').createSignedUrl(stored.substring(storagePrefix.length), 3600));
  }

  static String _guessMime(String name, {String? fallback}) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.pdf')) return 'application/pdf';
    return fallback ?? 'application/octet-stream';
  }
}
