import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class CreateRoomScreen extends ConsumerStatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  ConsumerState<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends ConsumerState<CreateRoomScreen> {
  final _roomNameController = TextEditingController();

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    final roomName = _roomNameController.text.trim();
    if (roomName.isEmpty) return;

    try {
      await ref.read(roomNotifierProvider.notifier).createRoom(roomName);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('部屋の作成に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('部屋を作成')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              '新しいチャットルームを作成します',
              style: TextStyle(fontSize: 14, color: Color(0xFF9E7B8A)),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _roomNameController,
              decoration: const InputDecoration(
                labelText: '部屋名',
                hintText: '例: 雑談部屋',
                prefixIcon: Icon(Icons.meeting_room_rounded),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _createRoom(),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRoom,
        icon: const Icon(Icons.check),
        label: const Text('作成', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
