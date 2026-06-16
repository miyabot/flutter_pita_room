import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends ConsumerState<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isResending = false;

  // 「確認しました」→ Firebaseのユーザー情報を再読み込みして emailVerified を確認
  Future<void> _checkVerified() async {
    setState(() => _isChecking = true);
    try {
      // reload() でサーバーから最新の認証状態を取得
      await ref.read(authProvider).currentUser?.reload();
      await ref.read(authProvider).currentUser?.getIdToken(true);
      final isVerified = ref.read(authProvider).currentUser?.emailVerified ?? false;

      if (!isVerified && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('まだ確認が完了していません。メールのリンクをタップしてください。')),
        );
      }
      // 認証済みなら main.dart のルーティングが自動で切り替わる
      // （authStateProvider が更新されるため）
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  // 確認メールを再送信
  Future<void> _resendEmail() async {
    setState(() => _isResending = true);
    try {
      await ref.read(authProvider).currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('確認メールを再送信しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.read(authProvider).currentUser?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('📧', style: TextStyle(fontSize: 64), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              const Text(
                'メールを確認してください',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2D1B33)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '$email\nに確認メールを送信しました。\nメール内のリンクをタップしてから\n下のボタンを押してください。',
                style: const TextStyle(fontSize: 14, color: Color(0xFF9E7B8A), height: 1.7),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              if (_isChecking)
                const Center(child: CircularProgressIndicator(color: Color(0xFFE91E8C)))
              else
                ElevatedButton(
                  onPressed: _checkVerified,
                  child: const Text('確認しました'),
                ),
              const SizedBox(height: 12),
              if (_isResending)
                const Center(child: CircularProgressIndicator(color: Color(0xFFE91E8C)))
              else
                OutlinedButton(
                  onPressed: _resendEmail,
                  child: const Text('メールを再送信'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await ref.read(authProvider).signOut();
                },
                child: const Text('ログアウト'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
