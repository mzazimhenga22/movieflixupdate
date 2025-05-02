import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Use hive_flutter
import 'firebase_options.dart';
import 'package:movie_app/splash_screen.dart';
import 'package:movie_app/settings_provider.dart';
import 'package:provider/provider.dart'; // Added provider import

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Hive for all platforms
    await Hive.initFlutter();
    await Hive.openBox('streaming_cache');
    debugPrint('✅ Hive initialized');

    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ Firebase initialized');
  } catch (e) {
    debugPrint('❌ Initialization error: $e');
    rethrow; // Optional: rethrow to halt app if initialization fails
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => SettingsProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: SplashScreen(),
    );
  }
}
