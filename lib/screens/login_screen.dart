import 'package:pita_room/utils/app_links.dart';
import 'package:pita_room/utils/auth_error_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _passwordVisible = false;

  //画面破棄時にコントローラーを解放する関数
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  //パスワードリセットメールを送信する関数
  Future<void> _resetPassword() async {
    String resetEmail = _emailController.text.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('パスワードをリセット'),
        content: TextField(
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'メールアドレス',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          onChanged: (value) => resetEmail = value,
          controller: TextEditingController(text: resetEmail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('送信'),
          ),
        ],
      ),
    );

    if (confirmed != true || resetEmail.isEmpty) return;

    try {
      await ref.read(authProvider).sendPasswordResetEmail(email: resetEmail);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('パスワードリセットメールを送信しました')));
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(e.code))));
      }
    }
  }

  //メールアドレスとパスワードでログインする関数
  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      await ref
          .read(authProvider)
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
    } on FirebaseAuthException catch (e) {
      final message = authErrorMessage(e.code);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  //ログイン画面のUIを構築する関数
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ロゴヘッダー
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 56),
                decoration: const BoxDecoration(
                  color: Color(0xFFFCE4EC),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE91E8C), width: 2),
                  ),
                ),
                child: Column(
                  children: [
                    Image.asset('assets/images/fairy.png', height: 120),
                    const SizedBox(height: 12),
                    const Text(
                      'ぴたルム',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE91E8C),
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '趣味・好みで相性を知ろう',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9E7B8A)),
                    ),
                  ],
                ),
              ),

              // フォームエリア
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'メールアドレス',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'パスワード',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _passwordVisible
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _passwordVisible = !_passwordVisible,
                          ),
                        ),
                      ),
                      obscureText: !_passwordVisible,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resetPassword,
                        child: const Text('パスワードをお忘れの方'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFE91E8C),
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _login,
                          child: const Text('ログイン'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: const Text('アカウントをお持ちでない方はこちら'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () =>
                                launchUrl(Uri.parse(kPrivacyPolicyUrl)),
                            child: const Text(
                              'プライバシーポリシー',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFAD5D7A),
                              ),
                            ),
                          ),
                          const Text(
                            '・',
                            style: TextStyle(color: Color(0xFFAD5D7A)),
                          ),
                          TextButton(
                            onPressed: () =>
                                launchUrl(Uri.parse(kTermsOfServiceUrl)),
                            child: const Text(
                              '利用規約',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFAD5D7A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
