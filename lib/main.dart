import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'services/crash_log_service.dart';
import 'utils/strings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupCrashHandlers();
  await crashLogService.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.white,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    statusBarColor: Color(0xFF2BBCC4),
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  ));

  await SharedPreferences.getInstance();
  await S.load();
  runApp(
    const ProviderScope(
      child: InheritedLangWrapper(
        child: SdrPrinterApp(),
      ),
    ),
  );
}

/// Wrapper that rebuilds children when language changes
class InheritedLangWrapper extends StatelessWidget {
  final Widget child;
  const InheritedLangWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: langProvider,
      builder: (context, child) => child!,
      child: child,
    );
  }
}

class SdrPrinterApp extends StatelessWidget {
  const SdrPrinterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dPrinter Mart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2BBCC4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2BBCC4),
          foregroundColor: Colors.white,
          elevation: 2,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
