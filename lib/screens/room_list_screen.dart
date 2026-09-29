import 'package:pita_room/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../providers.dart';
import '../utils/constants.dart';
import 'chat_screen.dart';
import 'create_room_screen.dart';

class RoomListScreen extends ConsumerStatefulWidget {
  const RoomListScreen({super.key});

  @override
  ConsumerState<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends ConsumerState<RoomListScreen> {
  final GlobalKey _fabKey = GlobalKey();
  final GlobalKey _profileKey = GlobalKey();

  bool _roomListDone = false;
  bool _tutorialLoaded = false;

  //初回起動時のウェルカムダイアログを表示する関数
  void _showWelcomeOverlay() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      barrierDismissible: false,
      builder: (context) => _WelcomeDialog(
        onFinished: () async {
          Navigator.pop(context);
          _showCoachMark();
          final uid = ref.read(authProvider).currentUser?.uid;
          if (uid == null) return;
          final query = await ref
              .read(firestoreProvider)
              .collection('users')
              .where('uid', isEqualTo: uid)
              .get();
          if (query.docs.isEmpty) return;
          await query.docs.first.reference.update({'tutorial.roomList': true});
        },
      ),
    );
  }

  //FABとプロフィールボタンを説明するコーチマークを表示する関数
  void _showCoachMark() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'fab',
          keyTarget: _fabKey,
          paddingFocus: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.top,
              padding: const EdgeInsets.only(left: 24, bottom: 32),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '部屋を作成',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(1, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'ここから友達とのルームを作れるよ',
                    style: TextStyle(
                      color: Color(0xFFFFCDD2),
                      fontSize: 14,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(1, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'profile',
          keyTarget: _profileKey,
          paddingFocus: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'プロフィール',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'アイコンや名前を設定しよう',
                    style: TextStyle(color: Color(0xFFFFCDD2), fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
      textSkip: 'スキップ',
      alignSkip: Alignment.topLeft,
      opacityShadow: 0.85,
    ).show(context: context);
  }

  //画面初期化時にチュートリアル状態を読み込む関数
  @override
  void initState() {
    super.initState();
    _loadTutorialStatus();
  }

  //チュートリアルを表示済みかFirestoreから取得する関数
  Future<void> _loadTutorialStatus() async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) return;
    final query = await ref
        .read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    if (!mounted) return;
    final tutorialMap = query.docs.isEmpty
        ? null
        : query.docs.first.data()['tutorial'];
    setState(() {
      if (tutorialMap is Map) {
        _roomListDone = tutorialMap['roomList'] == true;
      }
      _tutorialLoaded = true;
    });
  }

  //ルーム一覧画面のUIを構築する関数
  @override
  Widget build(BuildContext context) {
    final roomListState = ref.watch(roomsProvider);

    return roomListState.when(
      data: (rooms) {
        if (_tutorialLoaded && !_roomListDone) {
          _roomListDone = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Future.delayed(kTutorialShowDelay);
            if (mounted) _showWelcomeOverlay();
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('ルーム一覧'),
            actions: [
              IconButton(
                key: _profileKey,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
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
                      const Text('💬', style: TextStyle(fontSize: 64)),
                      const SizedBox(height: 16),
                      const Text(
                        '参加している部屋がありません',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF9E7B8A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '右下のボタンから部屋を作成しましょう',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFAD5D7A),
                        ),
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
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(roomId: room.id),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFCE4EC),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFFFFCDD2),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.meeting_room_rounded,
                                  color: Color(0xFFE91E8C),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  room.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF2D1B33),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF9E7B8A),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
          floatingActionButton: FloatingActionButton.extended(
            key: _fabKey,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateRoomScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text(
              '部屋を作成',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE91E8C)),
        ),
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

class _WelcomeDialog extends StatefulWidget {
  final VoidCallback onFinished;
  const _WelcomeDialog({required this.onFinished});

  @override
  State<_WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends State<_WelcomeDialog> {
  static const _messages = [
    'ようこそ ぴたルムへ！',
    '友達と相性診断ゲームを\n一緒に楽しめるアプリだよ！',
    'まずは部屋を作って\n友達を招待してみてね！',
  ];
  int _index = 0;

  //次のセリフに進む(最後なら完了コールバックを呼ぶ)関数
  void _next() {
    if (_index < _messages.length - 1) {
      setState(() => _index++);
    } else {
      widget.onFinished();
    }
  }

  //ウェルカムダイアログのUIを構築する関数
  @override
  Widget build(BuildContext context) {
    final isLast = _index == _messages.length - 1;
    return GestureDetector(
      onTap: _next,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            const Spacer(),
            // フェアリー画像
            Image.asset('assets/images/fairy.png', height: 180),
            const SizedBox(height: 4),
            // セリフウィンドウ
            Container(
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F8),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFE91E8C), width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66E91E8C),
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 名前プレート
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE91E8C),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(2),
                        topRight: Radius.circular(2),
                      ),
                    ),
                    child: const Text(
                      'ぴたルムのフェアリー',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // セリフ本文
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _messages[_index],
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2D1B33),
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            // ページドット
                            ...List.generate(
                              _messages.length,
                              (i) => Container(
                                margin: const EdgeInsets.only(right: 5),
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _index
                                      ? const Color(0xFFE91E8C)
                                      : const Color(0xFFFFCDD2),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              isLast ? '▶ はじめる！' : '▼ タップして続ける',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9E7B8A),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 52),
          ],
        ),
      ),
    );
  }
}
