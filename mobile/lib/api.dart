import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Đổi địa chỉ API khi chạy:  flutter run --dart-define=API_URL=http://192.168.1.10:8080/api
/// - Android emulator: 10.0.2.2 (mặc định)   - Web/Desktop/iOS simulator: http://localhost:8080/api
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080/api');

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static final Api i = Api._();

  late final Dio dio;
  final ValueNotifier<bool> loggedIn = ValueNotifier(false);
  String? token;
  Map<String, dynamic>? user;

  Api._() {
    dio = Dio(BaseOptions(
      baseUrl: apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  String get role => (user?['role'] ?? '') as String;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    final u = p.getString('user');
    if (u != null) user = Map<String, dynamic>.from(jsonDecode(u));
    loggedIn.value = token != null && user != null;
  }

  Future<void> login(String email, String password) async {
    final r = await _wrap(() => dio.post('/auth/login', data: {'email': email, 'password': password}));
    token = r['token'] as String;
    user = Map<String, dynamic>.from(r['user']);
    final p = await SharedPreferences.getInstance();
    await p.setString('token', token!);
    await p.setString('user', jsonEncode(user));
    loggedIn.value = true;
  }

  Future<void> logout() async {
    token = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
    loggedIn.value = false;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get(path, queryParameters: query));
  Future<dynamic> post(String path, [dynamic data]) => _changed(_wrap(() => dio.post(path, data: data)));
  Future<dynamic> put(String path, [dynamic data]) => _changed(_wrap(() => dio.put(path, data: data)));
  Future<dynamic> delete(String path) => _changed(_wrap(() => dio.delete(path)));

  /// Tăng mỗi khi thêm/sửa/xóa thành công: các trang tổng hợp (Trang chủ) lắng nghe để tự tải lại.
  final ValueNotifier<int> changes = ValueNotifier(0);

  Future<dynamic> _changed(Future<dynamic> f) async {
    final r = await f;
    changes.value++;
    return r;
  }

  Future<dynamic> _wrap(Future<Response> Function() f) async {
    try {
      return (await f()).data;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 && token != null) await logout(); // token hết hạn
      final d = e.response?.data;
      throw ApiException(d is Map && d['message'] != null
          ? '${d['message']}'
          : (e.response == null ? 'Không kết nối được máy chủ' : 'Lỗi $code'));
    }
  }
}
