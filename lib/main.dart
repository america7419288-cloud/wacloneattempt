import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';
import 'theme_provider.dart';
import 'wallpaper_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await WallpaperService.instance.load();
  runApp(const WACApp());
}

class WACApp extends StatelessWidget {
  const WACApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (context, isDark, _) {
        return CupertinoApp(
          title: 'WhatsApp',
          debugShowCheckedModeBanner: false,
          theme: isDark ? darkTheme : lightTheme,
          home: const HomeScreen(),
        );
      },
    );
  }
}
