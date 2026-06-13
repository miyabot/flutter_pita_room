import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../providers.dart';
import 'invite_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;

  const ChatScreen({
    super.key,
    required this.roomId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _messageController = TextEditingController();
  final _expandedAnswers = <String>{};

  late final String? _currentUid;
  late final GameNotifier _gameNotifier;

  final GlobalKey _gameButtonKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey();
  static bool _chatTutorialShown = false;

  @override
  void initState() {
    super.initState();
    _currentUid = ref.read(authProvider).currentUser?.uid;
    _gameNotifier = ref.read(gameNotifierProvider.notifier);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentUid != null) {
        _gameNotifier.joinGame(widget.roomId, _currentUid);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    if (_currentUid != null) {
      _gameNotifier.leaveGame(widget.roomId, _currentUid);
    }
    super.dispose();
  }

  void _showChatCoachMark() {
    TutorialCoachMark(
      targets: [
        TargetFocus(
          identify: 'gameButton',
          keyTarget: _gameButtonKey,
          paddingFocus: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ゲームを開始',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 4)],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '全員が揃ったらここからゲームを始めよう！',
                    style: TextStyle(
                      color: Color(0xFFFFCDD2),
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        TargetFocus(
          identify: 'menu',
          keyTarget: _menuKey,
          paddingFocus: 8,
          enableOverlayTab: true,
          contents: [
            TargetContent(
              align: ContentAlign.bottom,
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'メニュー',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 4)],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '友達の招待やルーム名の変更はここから',
                    style: TextStyle(
                      color: Color(0xFFFFCDD2),
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 4)],
                    ),
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

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final user = ref.read(authProvider).currentUser;
    if (user == null) return;

    _messageController.clear();

    try {
      await ref.read(firestoreProvider)
          .collection('rooms')
          .doc(widget.roomId)
          .collection('messages')
          .add({
        'text': text,
        'uid': user.uid,
        'email': user.email,
        'type': 'chat',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('メッセージの送信に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messageState = ref.watch(messagesProvider(widget.roomId));
    final roomState    = ref.watch(currentRoomStateProvider(widget.roomId));
    // gameState.activeMembers（Firestore）ではなく RTDB のプレゼンスを参照する
    // タスクキル時も onDisconnect で自動削除されるため常に正確な値になる
    final activeMembers = ref.watch(activeMembersProvider(widget.roomId)).value ?? [];

    return roomState.when(
      data: (room) {
        final gameState = room.gameState;
        final rawStatus = gameState.status;
        final currentUid = ref.read(authProvider).currentUser?.uid;

        final closedMembers = gameState.closedMembers;
        final hasClosedResult = closedMembers.contains(currentUid);
        final status = (rawStatus == 'result' && hasClosedResult) ? 'waiting' : rawStatus;

        if (!_chatTutorialShown && status == 'waiting') {
          _chatTutorialShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await Future.delayed(const Duration(milliseconds: 400));
            if (mounted) _showChatCoachMark();
          });
        }

        return SafeArea(
          child: Scaffold(
            appBar: AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    room.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 7, color: Color(0xFF4CAF50)),
                      const SizedBox(width: 4),
                      Text(
                        '${activeMembers.length}人 オンライン',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E7B8A),
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                if (status == 'waiting')
                  IconButton(
                    key: _gameButtonKey,
                    icon: const Icon(Icons.sports_esports),
                    tooltip: 'ゲーム開始',
                    onPressed: () {
                      if (activeMembers.length < 2) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ゲームは2人以上で開始できます'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      ref.read(gameNotifierProvider.notifier).startGame(
                        widget.roomId,
                        activeMembers,
                      );
                    },
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.pause_circle_outline),
                    tooltip: 'ゲームを強制終了',
                    onPressed: () {
                      ref.read(gameNotifierProvider.notifier).endGame(
                        widget.roomId,
                      );
                    },
                  ),
                PopupMenuButton<String>(
                  key: _menuKey,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    switch (value) {
                      case 'invite':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InviteScreen(roomId: widget.roomId),
                          ),
                        );
                        break;

                      case 'rename':
                        final nameController = TextEditingController();
                        final newName =await showDialog<bool>(
                          context: context, 
                          builder: (context)=>AlertDialog(
                            title:const Text('ルーム名の変更'),
                            content: TextField(
                              controller: nameController,
                              decoration: InputDecoration(
                                labelText: '新しいルーム名'
                              ),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('キャンセル'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('変更'),
                              ),
                            ],
                          )
                        );
                        nameController.dispose();
                        if(newName != true) return;
                        if(!context.mounted) return;
                        await ref.read(roomNotifierProvider.notifier).renameRoom(widget.roomId,nameController.text);
                        break;

                      case 'leave':
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('ルームを退会'),
                            content: const Text('このルームから退会しますか？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('キャンセル'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('退会する'),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        if (!context.mounted) return;
                        await ref.read(roomNotifierProvider.notifier)
                            .leaveRoom(widget.roomId);
                        if (context.mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                        break;
                      case 'logout':
                        await ref.read(authProvider).signOut();
                        if (context.mounted) {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        }
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'invite',
                      child: Row(
                        children: [
                          Icon(Icons.person_add),
                          SizedBox(width: 8),
                          Text('ユーザーを招待'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit),
                          SizedBox(width: 8),
                          Text('ルーム名の変更'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(Icons.exit_to_app),
                          SizedBox(width: 8),
                          Text('ルームを退会'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout),
                          SizedBox(width: 8),
                          Text('ログアウト'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: Column(
              children: [
                // ─── 出題パネル ───
                if (status == 'playing')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFCE4EC),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE91E8C), width: 2),
                      ),
                    ),
                    // Builder でインデックス計算を行い、正しい問題データを取得する
                    child: Builder(builder: (context) {
                      // questionIndices = startGame時にランダム選択した問題番号の配列
                      // currentQuestion = 今何問目か（0〜4）
                      // actualIndex = kQuestionsの実際のインデックス
                      final indices     = gameState.questionIndices;
                      final q           = gameState.currentQuestion;
                      final actualIndex = indices.isNotEmpty && q < indices.length
                          ? indices[q]
                          : q % kQuestions.length;
                      final questionData = kQuestions[actualIndex];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 進捗表示
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${q + 1} / ${gameState.totalQuestions}問',
                                style: const TextStyle(
                                  color: Color(0xFFE91E8C),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // 自分が回答済みか表示
                              if (gameState.answers.containsKey(currentUid))
                                const Text(
                                  '✅ 回答済み',
                                  style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12),
                                )
                              else
                                const Text(
                                  '回答してください',
                                  style: TextStyle(color: Color(0xFF9E7B8A), fontSize: 12),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // お題テキスト
                          Text(
                            questionData['question'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF2D1B33),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 4択ボタン
                          ...(questionData['choices'] as List)
                              .asMap()
                              .entries
                              .map((entry) {
                            final index      = entry.key;
                            final choice     = entry.value as String;
                            final hasAnswered = gameState.answers.containsKey(currentUid);
                            final myAnswer   = gameState.answers[currentUid];
                            final isSelected = myAnswer == index;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ElevatedButton(
                                onPressed: hasAnswered
                                    ? null // 回答済みなら押せない
                                    : () async {
                                        if (currentUid == null) return;
                                        await ref.read(gameNotifierProvider.notifier)
                                            .submitAnswer(
                                              widget.roomId,
                                              currentUid,
                                              index,
                                              activeMembers,
                                            );
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected
                                      ? const Color(0xFFE91E8C)
                                      : const Color(0xFFF8BBD0),
                                  foregroundColor: isSelected ? Colors.white : const Color(0xFF2D1B33),
                                  side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFFAD1461)
                                        : const Color(0xFFFFCDD2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(choice),
                              ),
                            );
                          }),

                          const SizedBox(height: 8),

                          // 何人が回答済みか表示
                          Text(
                            '${gameState.answers.length} / ${gameState.activeMembers.length}人が回答済み',
                            style: const TextStyle(
                              color: Color(0xFF9E7B8A),
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      );
                    }),
                  ),

                // ─── チャット一覧 ───
                if (status == 'waiting')
                  Expanded(
                    child: messageState.when(
                      data: (messages) {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe = message.uid == currentUid;

                            final nameAsync = ref.watch(userNameProvider(message.uid));
                            final nameSnapshot = nameAsync.value;
                            final name = (nameSnapshot == null || nameSnapshot.isEmpty) ? '' : nameSnapshot;

                            final avatarUrl = ref.watch(userAvatarProvider(message.uid)).value ?? '';

                            if (message.type == 'game_session') {
    final isExpanded = _expandedAnswers.contains(message.id);
    final rounds = message.rounds;
    final scores = message.scores;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE91E8C), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33E91E8C),
            offset: Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedAnswers.remove(message.id);
            } else {
              _expandedAnswers.add(message.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Text('🎮', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    'ゲーム結果（${rounds.length}問）',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFE91E8C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Color(0xFFE91E8C),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
            // 展開時
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Column(
                      children: [
                        const Divider(color: Color(0xFFFFCDD2), height: 1),
                        // マッチング結果
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'マッチング結果',
                                style: TextStyle(
                                  color: Color(0xFFE91E8C),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...scores.entries.map((entry) {
                                final keys    = entry.key.split('_');
                                final uid1    = keys[0];
                                final uid2    = keys[1];
                                final score   = entry.value;
                                final total   = rounds.length;
                                final percent = total > 0
                                    ? (score / total * 100).round()
                                    : 0;
                                final name1 = ref.watch(userNameProvider(uid1)).value ?? '...';
                                final name2 = ref.watch(userNameProvider(uid2)).value ?? '...';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Text(
                                        '$name1 × $name2',
                                        style: const TextStyle(
                                          color: Color(0xFF2D1B33),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '$percent%',
                                        style: TextStyle(
                                          color: percent >= 60
                                              ? const Color(0xFF4CAF50)
                                              : const Color(0xFF9E7B8A),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const Divider(color: Color(0xFFFFCDD2), height: 1),
                        // 各問の回答
                        ...rounds.asMap().entries.map((entry) {
                          final i       = entry.key;
                          final round   = entry.value;
                          final question = round['question'] as String? ?? '';
                          final choices  = round['choices']  as List<dynamic>? ?? [];
                          final answers  = round['answers']  as Map<String, dynamic>? ?? {};
                          final isLast   = i == rounds.length - 1;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(14, 10, 14, isLast ? 14 : 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      question,
                                      style: const TextStyle(
                                        color: Color(0xFFE91E8C),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ...answers.entries.map((answer) {
                                      final uid         = answer.key;
                                      final choiceIndex = answer.value as int;
                                      final choiceText  = choiceIndex < choices.length
                                          ? choices[choiceIndex] as String
                                          : '?';
                                      final userName = ref.watch(userNameProvider(uid)).value ?? '...';

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          children: [
                                            Text(
                                              userName,
                                              style: const TextStyle(
                                                color: Color(0xFF2D1B33),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const Text('：',
                                              style: TextStyle(color: Color(0xFF9E7B8A)),
                                            ),
                                            Text(
                                              choiceText,
                                              style: const TextStyle(
                                                color: Color(0xFF2D1B33),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                              if (!isLast)
                                const Divider(
                                  color: Color(0xFFFFCDD2),
                                  height: 1,
                                  indent: 14,
                                  endIndent: 14,
                                ),
                            ],
                          );
                        }),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

                            // 通常チャット
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children:[ 
                                  if(!isMe)...[
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: const Color(0xFFFCE4EC),
                                      backgroundImage: avatarUrl.isNotEmpty
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                      child: avatarUrl.isEmpty
                                          ? const Icon(Icons.person, size: 16, color: Color(0xFF9E7B8A))
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Column(
                                  crossAxisAlignment: isMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe && name.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4, bottom: 2),
                                        child: Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9E7B8A),
                                          ),
                                        ),
                                      ),
                                    Container(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.of(context).size.width * 0.65,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? const Color(0xFFE91E8C)
                                            : const Color(0xFFF8BBD0),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(4),
                                          topRight: const Radius.circular(4),
                                          bottomLeft: Radius.circular(isMe ? 4 : 0),
                                          bottomRight: Radius.circular(isMe ? 0 : 4),
                                        ),
                                        border: Border.all(
                                          color: isMe
                                              ? const Color(0xFFAD1461)
                                              : const Color(0xFFFFCDD2),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Text(
                                        message.text,
                                        style: TextStyle(
                                          color: isMe ? Colors.white : const Color(0xFF2D1B33),
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                ]
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFE91E8C)),
                      ),
                      error: (error, stack) => Center(
                        child: Text('メッセージ取得エラー: $error'),
                      ),
                    ),
                  ),

                if (status == 'result')
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFCE4EC),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE91E8C), width: 2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '🎉 結果発表！',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D1B33),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // 全員とのマッチング率を表示
                        ...gameState.activeMembers
                            .where((uid) => uid != currentUid)
                            .map((uid) {
                          // スコアキーは uid1_uid2 の形式
                          // uid1 < uid2 になるように並べる
                          final sortedUids = [currentUid!, uid]..sort();
                          final key = '${sortedUids[0]}_${sortedUids[1]}';

                          final score = gameState.scores[key] ?? 0;
                          final total = gameState.totalQuestions;
                          final percent = (score / total * 100).round();

                          final nameAsync = ref.watch(userNameProvider(uid));
                          final name = nameAsync.value ?? '...';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Color(0xFF2D1B33),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '$percent%',
                                      style: TextStyle(
                                        color: percent >= 60
                                            ? const Color(0xFF4CAF50)
                                            : const Color(0xFF9E7B8A),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // プログレスバー
                                LinearProgressIndicator(
                                  value: percent / 100,
                                  backgroundColor: const Color(0xFFF8BBD0),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    percent >= 60
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFFE91E8C),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            if (currentUid == null) return;
                            ref.read(gameNotifierProvider.notifier)
                                .closeResult(widget.roomId, currentUid, gameState.activeMembers);
                          },
                          child: const Text('結果を閉じる'),
                        ),
                      ],
                    ),
                  ),

                // ─── メッセージ入力バー ───
                if (status == 'waiting')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Color(0xFFFFCDD2)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'メッセージを入力...',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
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
                              filled: true,
                              fillColor: const Color(0xFFF8BBD0),
                            ),
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE91E8C),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFAD1461), width: 1.5),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send_rounded, color: Colors.white),
                            onPressed: _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE91E8C))),
      ),
      error: (error, stack) => Scaffold(
        body: Center(child: Text('ルームデータの読み込みエラー: $error')),
      ),
    );
  }
}
