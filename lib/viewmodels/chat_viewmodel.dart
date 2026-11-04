import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/questions.dart';
import '../models/message_model.dart';
import 'firebase_providers.dart';

final messagesProvider = StreamProvider.family<List<MessageModel>, String>((
  ref,
  roomId,
) {
  return ref
      .watch(firestoreProvider)
      .collection('rooms')
      .doc(roomId)
      .collection('messages')
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map((doc) => MessageModel.fromDocument(doc)).toList(),
      );
});

// Firestoreのactive membersはタスクキル時に更新されないため、
// RTDBのonDisconnectでプレゼンス管理して現在の在室メンバーを取得する
final activeMembersProvider = StreamProvider.family<List<String>, String>((
  ref,
  roomId,
) {
  return ref
      .watch(databaseProvider)
      .ref('rooms/$roomId/activeMembers')
      .onValue
      .map((event) {
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) return <String>[];
        return data.keys.map((k) => k.toString()).toList();
      });
});

class ChatNotifier extends Notifier<void> {
  //チャットメッセージを送信する関数
  Future<void> sendMessage(String roomId, String text) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;

    await ref
        .read(firestoreProvider)
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .add({
          'text': text,
          'uid': user.uid,
          'email': user.email,
          'type': 'chat',
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  //Riverpodの初期化用関数(状態は使わないので何もしない)
  @override
  void build() {}
}

final chatNotifierProvider = NotifierProvider<ChatNotifier, void>(
  ChatNotifier.new,
);

class GameNotifier extends Notifier<void> {
  //在室状態を登録する関数(タスクキル時に自動で消えるようonDisconnectも予約する)
  Future<void> joinGame(String roomId, String uid) async {
    try {
      final presenceRef = ref
          .read(databaseProvider)
          .ref('rooms/$roomId/activeMembers/$uid');
      await presenceRef.onDisconnect().remove();
      await presenceRef.set(true);
    } catch (e) {
      debugPrint('joinGame エラー: $e');
    }
  }

  //在室状態を解除する関数
  Future<void> leaveGame(String roomId, String uid) async {
    final presenceRef = ref
        .read(databaseProvider)
        .ref('rooms/$roomId/activeMembers/$uid');
    await presenceRef.onDisconnect().cancel();
    await presenceRef.remove();
  }

  //ゲームを開始する関数(kQuestionsからkQuestionsPerGame問をランダムに選んで出題順を決める)
  Future<void> startGame(String roomId, List<String> activeMembers) async {
    final allIndices = List.generate(kQuestions.length, (i) => i)
      ..shuffle(Random());
    final selectedIndices = allIndices.take(kQuestionsPerGame).toList();

    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'gameState.status': 'playing',
      'gameState.currentQuestion': 0,
      'gameState.totalQuestions': kQuestionsPerGame,
      'gameState.answers': {},
      'gameState.scores': {},
      'gameState.rounds': [],
      'gameState.closedMembers': [],
      'gameState.activeMembers': activeMembers,
      'gameState.questionIndices': selectedIndices,
    });
  }

  //回答を送信する関数
  Future<void> submitAnswer(
    String roomId,
    String uid,
    int answerIndex,
    List<String> activeMembers,
  ) async {
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    // 読み取りと書き込みを1つの不可分な操作にまとめることで、
    // 複数人が同時に回答しても「全員回答済み」の判定が正しく行われるようにする
    final allAnswered = await ref.read(firestoreProvider).runTransaction((
      transaction,
    ) async {
      final snapshot = await transaction.get(docRef);
      final data = snapshot.data();
      if (data == null) return false;

      final gameState = Map<String, dynamic>.from(data['gameState'] ?? {});
      final answers = Map<String, dynamic>.from(gameState['answers'] ?? {});
      answers[uid] = answerIndex;

      transaction.update(docRef, {'gameState.answers.$uid': answerIndex});

      return activeMembers.every((memberId) => answers.containsKey(memberId));
    });

    if (allAnswered) {
      await nextQuestion(roomId, activeMembers);
    }
  }

  //次の問題に進める関数(最後の問題ならresult状態にする)
  Future<void> nextQuestion(String roomId, List<String> activeMembers) async {
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    final doc = await docRef.get();
    final data = doc.data();
    if (data == null) return;

    final gameState = data['gameState'] as Map<String, dynamic>? ?? {};
    final currentQ = gameState['currentQuestion'] as int? ?? 0;
    final totalQ = gameState['totalQuestions'] as int? ?? kQuestionsPerGame;
    final answersRaw = gameState['answers'] as Map<String, dynamic>? ?? {};
    final scoresRaw = gameState['scores'] as Map<String, dynamic>? ?? {};
    final roundsRaw = gameState['rounds'] as List<dynamic>? ?? [];
    final questionIndicesRaw =
        gameState['questionIndices'] as List<dynamic>? ?? [];
    final questionIndices = questionIndicesRaw.map((e) => e as int).toList();

    // ランダム選択済みのインデックスがあればそれを使い、なければcurrentQをそのまま使う
    final actualIndex =
        questionIndices.isNotEmpty && currentQ < questionIndices.length
        ? questionIndices[currentQ]
        : currentQ % kQuestions.length;

    final currentQuestionData = kQuestions[actualIndex];

    final newRound = {
      'question': currentQuestionData['question'],
      'choices': currentQuestionData['choices'],
      'answers': answersRaw,
    };

    final updatedRounds = [
      ...roundsRaw.map((e) => Map<String, dynamic>.from(e as Map)),
      newRound,
    ];

    // 2人ずつのペアで回答が一致していたらスコア+1
    final updatedScores = Map<String, int>.from(
      scoresRaw.map((key, value) => MapEntry(key, value as int)),
    );

    for (int i = 0; i < activeMembers.length; i++) {
      for (int j = i + 1; j < activeMembers.length; j++) {
        final uid1 = activeMembers[i];
        final uid2 = activeMembers[j];
        final sortedUids = [uid1, uid2]..sort();
        final key = '${sortedUids[0]}_${sortedUids[1]}';

        if (answersRaw[uid1] == answersRaw[uid2]) {
          updatedScores[key] = (updatedScores[key] ?? 0) + 1;
        }
      }
    }

    final isLastQuestion = currentQ + 1 >= totalQ;

    if (isLastQuestion) {
      await docRef.update({
        'gameState.status': 'result',
        'gameState.rounds': updatedRounds,
        'gameState.scores': updatedScores,
        'gameState.answers': {},
        'gameState.closedMembers': [],
      });
    } else {
      await docRef.update({
        'gameState.currentQuestion': currentQ + 1,
        'gameState.answers': {},
        'gameState.rounds': updatedRounds,
        'gameState.scores': updatedScores,
      });
    }
  }

  //ゲームを終了してwaiting状態に戻す関数
  Future<void> endGame(String roomId) async {
    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'gameState.status': 'waiting',
      'gameState.currentQuestion': 0,
      'gameState.answers': {},
      'gameState.scores': {},
      'gameState.rounds': [],
      'gameState.closedMembers': [],
    });
  }

  //結果画面を閉じる関数(全員が閉じたらendGame()を呼ぶ)
  Future<void> closeResult(
    String roomId,
    String uid,
    List<String> activeMembers,
  ) async {
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    await docRef.update({
      'gameState.closedMembers': FieldValue.arrayUnion([uid]),
    });

    final doc = await docRef.get();
    final data = doc.data();
    if (data == null) return;

    final gameState = data['gameState'] as Map<String, dynamic>? ?? {};
    final closedMembers = List<String>.from(gameState['closedMembers'] ?? []);

    final allClosed = activeMembers.every((m) => closedMembers.contains(m));

    if (allClosed) {
      // ゲーム結果をメッセージとして保存してから終了
      await ref
          .read(firestoreProvider)
          .collection('rooms')
          .doc(roomId)
          .collection('messages')
          .add({
            'type': 'game_session',
            'text': '',
            'uid': '',
            'email': '',
            'rounds': gameState['rounds'] ?? [],
            'scores': gameState['scores'] ?? {},
            'createdAt': FieldValue.serverTimestamp(),
          });

      await endGame(roomId);
    }
  }

  //Riverpodの初期化用関数(状態は使わないので何もしない)
  @override
  void build() {}
}

final gameNotifierProvider = NotifierProvider<GameNotifier, void>(
  GameNotifier.new,
);
