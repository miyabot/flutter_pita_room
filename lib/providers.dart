import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:pita_room/models/user_model.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/room_model.dart';
import 'models/message_model.dart';
import 'data/questions.dart';
import 'utils/constants.dart';

//ゲームを開始できる最小人数
const kMinPlayersToStart = 2;

// テスト時にモックへ差し替えられるようFirebaseインスタンスをDIする
final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final storageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);
// RTDBはタスクキル時のプレゼンス管理（onDisconnect）専用
// databaseURL は Firebase コンソール → Realtime Database の上部に表示されている URL
final databaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://bomb-chat-6da2d-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authProvider).idTokenChanges();
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return null;
        return UserModel.fromDocument(snapshot.docs.first);
      });
});

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

final userAvatarProvider = StreamProvider.family<String, String>((ref, uid) {
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return '';
        return snapshot.docs.first.data()['avatarUrl'] as String? ?? '';
      });
});

final roomsProvider = StreamProvider<List<RoomModel>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);

  return ref
      .watch(firestoreProvider)
      .collection('rooms')
      .where('members', arrayContains: uid)
      .orderBy('createdAt', descending: false) // リストの順序を一定にするため作成日時の昇順でソート
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map((doc) => RoomModel.fromDocument(doc)).toList(),
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

final currentRoomStateProvider = StreamProvider.family<RoomModel, String>((
  ref,
  roomId,
) {
  return ref
      .watch(firestoreProvider)
      .collection('rooms')
      .doc(roomId)
      .snapshots()
      .map((doc) => RoomModel.fromDocument(doc));
});

final userNameProvider = StreamProvider.family<String, String>((ref, uid) {
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return '';
        return snapshot.docs.first.data()['name'] as String? ?? '';
      });
});

//ルーム内の全メッセージを削除する関数(Firestoreは親を消してもサブコレクションが残るため先に削除する)
Future<void> _deleteRoomMessages(
  FirebaseFirestore firestore,
  String roomId,
) async {
  final messages = await firestore
      .collection('rooms')
      .doc(roomId)
      .collection('messages')
      .get();
  for (final message in messages.docs) {
    await message.reference.delete();
  }
}

class AuthNotifier extends AsyncNotifier<void> {
  //新規会員登録を行う関数
  Future<void> register(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final credential = await ref
          .read(authProvider)
          .createUserWithEmailAndPassword(email: email, password: password);

      // Notifierが破棄されても登録処理を完遂させるため、read()で直接書き込む
      await ref.read(firestoreProvider).collection('users').add({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'userId': _generateUserId(),
        'uid': credential.user!.uid,
        'name': '',
        'tutorial': {'roomList': false, 'chatRoom': false},
      });

      await credential.user!.sendEmailVerification();

      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  //招待用のランダムなユーザーIDを生成する関数
  String _generateUserId() {
    const chars = 'ACDEFGHJKMNPQRTUVWXY3479';
    final random = Random();
    return List.generate(
      kInviteCodeLength,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  //表示名を保存する関数
  Future<void> saveName(String name) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) return;
    final query = await ref
        .read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    if (query.docs.isEmpty) return;
    await query.docs.first.reference.update({'name': name});
  }

  //アバター画像をアップロードする関数
  Future<void> uploadAvatar(String filePath) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) return;

    final storageRef = ref
        .read(storageProvider)
        .ref()
        .child('avatars/$uid.jpg');
    await storageRef.putFile(File(filePath));
    final url = await storageRef.getDownloadURL();

    final query = await ref
        .read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    if (query.docs.isEmpty) return;
    await query.docs.first.reference.update({'avatarUrl': url});
  }

  //アカウントを完全に削除する関数(Firebaseは削除前に再認証が必要なためパスワードを受け取る)
  Future<void> deleteAccount(String password) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;

    final uid = user.uid;
    final email = user.email ?? '';

    // Firebaseはアカウント削除の前に再認証を要求する
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);

    // アバター画像を削除(未設定なら失敗するのでスキップする)
    try {
      await ref.read(storageProvider).ref('avatars/$uid.jpg').delete();
    } catch (_) {}

    // 参加中の全ルームから退会し、最後の1人なら部屋ごと削除する
    final roomQuery = await ref
        .read(firestoreProvider)
        .collection('rooms')
        .where('members', arrayContains: uid)
        .get();

    for (final doc in roomQuery.docs) {
      await doc.reference.update({
        'members': FieldValue.arrayRemove([uid]),
      });
      final updated = await doc.reference.get();
      final members = List<String>.from(updated.data()?['members'] ?? []);
      if (members.isEmpty) {
        await _deleteRoomMessages(ref.read(firestoreProvider), doc.id);
        await doc.reference.delete();
      }
    }

    // Firestoreのユーザードキュメントを削除
    final userQuery = await ref
        .read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    for (final doc in userQuery.docs) {
      await doc.reference.delete();
    }

    // Auth側の削除は最後に行う(先に消すと上の処理が権限エラーになる)
    await user.delete();
  }

  //Riverpodの初期化用関数(状態は使わないので何もしない)
  @override
  Future<void> build() async {}
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, void>(
  AuthNotifier.new,
);

class RoomNotifier extends Notifier<void> {
  //ルームを新規作成する関数
  Future<void> createRoom(String roomName) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) throw StateError('ログインユーザーが見つかりません');

    await ref.read(firestoreProvider).collection('rooms').add({
      'name': roomName,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'members': [uid],
      'gameState': {
        'status': 'waiting',
        'currentQuestion': 0,
        'totalQuestions': kQuestionsPerGame,
        'answers': {},
        'scores': {},
        'activeMembers': [],
        'closedMembers': [],
        'rounds': [],
        'questionIndices': [], // ゲーム開始時にランダム選択した問題のインデックス一覧
      },
    });
  }

  //ルームから退会する関数
  Future<void> leaveRoom(String roomId) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) return;

    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    await docRef.update({
      'members': FieldValue.arrayRemove([uid]),
    });

    final doc = await docRef.get();
    final data = doc.data();
    if (data == null) return;

    // 最後の1人が退会したらルームごと削除する
    final members = List<String>.from(data['members'] ?? []);
    if (members.isEmpty) {
      await _deleteRoomMessages(ref.read(firestoreProvider), roomId);
      await docRef.delete();
    }
  }

  //招待IDでユーザーをルームに追加する関数
  Future<bool> inviteUserByCode({
    required String roomId,
    required String inviteCode,
  }) async {
    final firestore = ref.read(firestoreProvider);
    final query = await firestore
        .collection('users')
        .where('userId', isEqualTo: inviteCode)
        .get();

    if (query.docs.isEmpty) return false;

    final targetUid = query.docs.first.data()['uid'] as String;
    await firestore.collection('rooms').doc(roomId).update({
      'members': FieldValue.arrayUnion([targetUid]),
    });

    return true;
  }

  //ルーム名を変更する関数
  Future<void> renameRoom(String roomId, String newName) async {
    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'name': newName,
    });
  }

  //Riverpodの初期化用関数(状態は使わないので何もしない)
  @override
  void build() {}
}

final roomNotifierProvider = NotifierProvider<RoomNotifier, void>(
  RoomNotifier.new,
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
