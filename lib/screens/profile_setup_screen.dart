import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../utils/constants.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;

  //画面破棄時にコントローラーを解放する関数
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  //表示名を保存する関数
  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(authNotifierProvider.notifier).saveName(name);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  //表示名設定画面のUIを構築する関数
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/images/fairy.png', height: 100),
              const SizedBox(height: 20),
              const Text(
                'ようこそ！',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D1B33),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'まずは表示名を設定してください',
                style: TextStyle(fontSize: 14, color: Color(0xFF9E7B8A)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              TextField(
                maxLength: kDisplayNameMaxLength,
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '表示名',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saveName(),
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFE91E8C)),
                )
              else
                ElevatedButton(
                  onPressed: _saveName,
                  child: const Text('はじめる！'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
