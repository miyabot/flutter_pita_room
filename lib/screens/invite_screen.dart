import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class InviteScreen extends ConsumerStatefulWidget {
  final String roomId;

  const InviteScreen({
    super.key,
    required this.roomId,
  });

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _userIdController = TextEditingController();

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  Future<void> _inviteUser() async {
    final inviteCode = _userIdController.text.trim();
    if (inviteCode.isEmpty) return;

    FocusScope.of(context).unfocus();

    try {
      final isSuccess = await ref.read(roomNotifierProvider.notifier).inviteUserByCode(
            roomId: widget.roomId,
            inviteCode: inviteCode,
          );

      if (mounted) {
        if (isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('追加しました！')),
          );
          _userIdController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ユーザーが見つかりませんでした')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('招待処理中にエラーが発生しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ユーザーを追加')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              '招待IDを入力してユーザーをルームに追加できます',
              style: TextStyle(fontSize: 14, color: Color(0xFF9E7B8A)),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(
                labelText: 'ユーザー招待ID（6桁）',
                prefixIcon: Icon(Icons.person_add_outlined),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _inviteUser(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _inviteUser,
              child: const Text('ユーザーを追加する'),
            ),
          ],
        ),
      ),
    );
  }
}
