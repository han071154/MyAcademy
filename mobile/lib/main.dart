import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'pages/home_page.dart';
import 'pages/login_page.dart';
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
        home: ValueListenableBuilder<bool>(
          valueListenable: Api.i.loggedIn,
          builder: (_, ok, __) => ok ? const HomePage() : const LoginPage(),
        ),
      );
}
