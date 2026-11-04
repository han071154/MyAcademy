import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/password_pages.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://epauixtqxgfwvcnhouio.supabase.co',
    publishableKey: 'sb_publishable_0qebfckLPxT68_3QwyiSnQ_konncBtK',
  );
  await Api.i.load();
  runApp(const CenterApp());
}

class CenterApp extends StatelessWidget {
  const CenterApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Quản lý trung tâm ngoại ngữ',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Đăng nhập/đăng xuất (kể cả token hết hạn) tự chuyển màn hình.
        home: ListenableBuilder(
          listenable: Listenable.merge([Api.i.loggedIn, Api.i.mustChangePassword]),
          builder: (_, __) {
            if (!Api.i.loggedIn.value) return const LoginPage();
            if (Api.i.mustChangePassword.value) return const ForceChangePasswordPage();
            return const HomePage();
          },
        ),
      );
}
