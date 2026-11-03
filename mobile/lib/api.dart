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

  final ValueNotifier<bool> loggedIn = ValueNotifier(false);
  final ValueNotifier<int> changes = ValueNotifier(0);

  String? token;
  Map<String, dynamic>? user;

  Api._();

  SupabaseClient get _sb => Supabase.instance.client;

  String get role => (user?['role'] ?? '') as String;
  int? get userId => user?['id'] != null ? int.tryParse(user!['id'].toString()) : null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    final u = p.getString('user');
    if (u != null) {
      try {
        user = Map<String, dynamic>.from(jsonDecode(u));
      } catch (_) {}
    }
    loggedIn.value = token != null && user != null;
  }

  Future<void> login(String email, String password) async {
    try {
      final res = await _sb.rpc('login', params: {
        'p_email': email,
        'p_password': password,
      });
      final map = Map<String, dynamic>.from(_unwrap(res));
      token = map['token'] as String? ?? 'active';
      user = Map<String, dynamic>.from(map['user']);
      final p = await SharedPreferences.getInstance();
      await p.setString('token', token!);
      await p.setString('user', jsonEncode(user));
      loggedIn.value = true;
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
    } catch (e) {
      throw ApiException(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> logout() async {
    token = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    loggedIn.value = false;
  }

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

  Future<dynamic> _wrap(Future<dynamic> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      throw ApiException(e.message);
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
      return await _sb.from('v_classes').select().order('id', ascending: false);
    }
    if (path == '/my/classes') {
      final res = await _sb.rpc('get_my_classes', params: {
        'p_user_id': userId,
        'p_role': role,
      });
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
      final res = await _sb.rpc('get_student_attendance', params: {
        'p_class_id': id,
        'p_student_id': userId,
      });
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
      return await _sb.from('users').select('id,email,full_name,role,phone').eq('id', userId!).single();
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
      final studentId = role == 'STUDENT'
          ? userId
          : (b['student_id'] != null ? int.parse(b['student_id'].toString()) : userId);
      final res = await _sb.rpc('enroll_student', params: {
        'p_class_id': classId,
        'p_student_id': studentId,
        'p_role': role,
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
        'submitted_at': DateTime.now().toIso8601String(),
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
      final res = await _sb.rpc('change_password', params: {
        'p_user_id': userId,
        'p_old_password': b['old_password'],
        'p_new_password': b['new_password'],
      });
      return _unwrap(res);
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
        'graded_at': DateTime.now().toIso8601String(),
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
      final res = await _sb.rpc('cancel_my_enrollment', params: {
        'p_class_id': classId,
        'p_student_id': userId,
      });
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
      await _sb.from('users').delete().eq('id', id);
      return;
    }

    throw ApiException('Đường dẫn không hợp lệ: $path');
  }

  Future<String> uploadFile(String fileName, Uint8List bytes, {String? mimeType}) async {
    try {
      final cleanName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path = '${DateTime.now().millisecondsSinceEpoch}_$cleanName';
      await _sb.storage.from('submissions').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: true),
      );
      return _sb.storage.from('submissions').getPublicUrl(path);
    } catch (_) {
      final mime = mimeType ??
          (fileName.toLowerCase().endsWith('.png')
              ? 'image/png'
              : (fileName.toLowerCase().endsWith('.jpg') || fileName.toLowerCase().endsWith('.jpeg')
                  ? 'image/jpeg'
                  : (fileName.toLowerCase().endsWith('.pdf') ? 'application/pdf' : 'application/octet-stream')));
      final base64Str = base64Encode(bytes);
      return 'data:$mime;base64,$base64Str';
    }
  }
}
