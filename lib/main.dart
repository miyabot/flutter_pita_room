import 'package:bomb_chat/screens/profile_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'providers.dart';
import 'screens/email_verification_screen.dart';
import 'screens/login_screen.dart';
import 'screens/room_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(
    const ProviderScope(child: MyApp())
  );
}

/// 認証状態を監視し、適切な初期画面へ宣言的にルーティングを制御するルートWidget
class MyApp extends ConsumerWidget {
  const MyApp({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      //locale: DevicePreview.locale(context),
      //builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'ぴたルム',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE91E8C),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.dotGothic16TextTheme(),
        scaffoldBackgroundColor: const Color(0xFFFFF5F8),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFFFF5F8),
          foregroundColor: const Color(0xFF2D1B33),
          elevation: 0,
          titleTextStyle: GoogleFonts.dotGothic16(
            color: const Color(0xFF2D1B33),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE91E8C),
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            textStyle: GoogleFonts.dotGothic16(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE91E8C), width: 1.5),
            foregroundColor: const Color(0xFFE91E8C),
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            textStyle: GoogleFonts.dotGothic16(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFF0F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFE91E8C), width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF9E7B8A)),
          hintStyle: const TextStyle(color: Color(0xFFAD5D7A)),
          prefixIconColor: const Color(0xFF9E7B8A),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE91E8C),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFE91E8C),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            side: BorderSide(color: Color(0xFFAD1461), width: 1.5),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF2D1B33),
          contentTextStyle: const TextStyle(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF9E7B8A)),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Color(0xFFFFCDD2), width: 1.5),
          ),
        ),
      ),
      home: authState.when(
        data: (user){
          if (user == null) {
            return const LoginScreen();
          }
          if (!user.emailVerified) {
            return const EmailVerificationScreen();
          }
          // nameが設定されているか確認
          return ref.watch(currentUserProvider).when(
            data: (userModel) {
              if (userModel == null || userModel.name.isEmpty) {
                return const ProfileSetupScreen(); // 名前未設定
              }
              return const RoomListScreen(); // 設定済み
            },
            loading: () => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
            error: (e, s) => const Scaffold(
              body: Center(child: CircularProgressIndicator(color: Color(0xFFE91E8C))),
            ),
          );
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stack) => Scaffold(
          body: Center(child: Text('認証エラーが発生しました: $error')),
        ),
      ),
    );
  }
}
