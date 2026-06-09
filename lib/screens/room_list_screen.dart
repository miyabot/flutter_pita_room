import 'package:bomb_chat/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'chat_screen.dart';
import 'create_room_screen.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  const RoomListScreen({super.key});

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> {
  @override
  Widget build(BuildContext context) {
    final roomListState = ref.watch(roomsProvider);

    return roomListState.when(
      data: (rooms) {
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Text('🔮', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('ルーム一覧'),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                },
                icon: const Icon(Icons.person_outline),
                tooltip: 'プロフィール',
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'ログアウト',
                onPressed: () async {
                  await ref.read(authProvider).signOut();
                },
              ),
            ],
          ),
          body: rooms.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🔮', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      const Text(
                        '参加している部屋がありません',
                        style: TextStyle(fontSize: 16, color: Color(0xFFB0B0C0)),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '右下のボタンから部屋を作成しましょう',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6060A0)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(roomId: room.id),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF251840),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.meeting_room_rounded,
                                  color: Color(0xFF6A1B9A),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  room.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Color(0xFFB0B0C0)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateRoomScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('部屋を作成', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6A1B9A))),
      ),
      error: (error, stack) {
        debugPrint('部屋一覧取得エラー: $error');
        return Scaffold(
          body: Center(
            child: Text(
              'エラーが発生しました。\n再度お試しください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[400]),
            ),
          ),
        );
      },
    );
  }
}
