import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:bomb_chat/models/user_model.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/room_model.dart';
import 'models/message_model.dart';
import 'data/questions.dart';

// テスト時のモック化やテスト容易性を高めるDI用プロバイダー
final authProvider      = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final storageProvider   = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);
// RTDBはタスクキル時のプレゼンス管理（onDisconnect）専用
// databaseURL は Firebase コンソール → Realtime Database の上部に表示されている URL
final databaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://bomb-chat-6da2d-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authProvider).idTokenChanges();
});

final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);

  return ref.watch(firestoreProvider)
      .collection('users')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return null;
        return UserModel.fromDocument(snapshot.docs.first);
      });
});

final messagesProvider = StreamProvider.family<List<MessageModel>, String>((ref, roomId) {
  return ref.watch(firestoreProvider)
      .collection('rooms')
      .doc(roomId)
      .collection('messages')
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => MessageModel.fromDocument(doc)).toList());
});

final userAvatarProvider = StreamProvider.family<String,String>((ref,uid){
  return ref.watch(firestoreProvider)
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
  
  return ref.watch(firestoreProvider)
      .collection('rooms')
      .where('members', arrayContains: uid)
      .orderBy('createdAt', descending: false) // リストの順序を一定にするため作成日時の昇順でソート
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => RoomModel.fromDocument(doc)).toList());
});

/// RTDBで現在チャット画面を開いているメンバーのUID一覧をリアルタイム監視する
///
/// Firestoreの gameState.activeMembers はタスクキル時に更新されないため、
/// RTDBのonDisconnect機能を使ってプレゼンス管理を行う。
/// パス: rooms/{roomId}/activeMembers/{uid} = true
final activeMembersProvider = StreamProvider.family<List<String>, String>((ref, roomId) {
  return ref.watch(databaseProvider)
      .ref('rooms/$roomId/activeMembers')
      .onValue
      .map((event) {
        // RTDBの値は Map<dynamic, dynamic> で届く
        // キーが uid、値が true なので、キー一覧を String リストに変換する
        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data == null) return <String>[];
        return data.keys.map((k) => k.toString()).toList();
      });
});

final currentRoomStateProvider = StreamProvider.family<RoomModel, String>((ref, roomId) {
  return ref.watch(firestoreProvider)
      .collection('rooms')
      .doc(roomId)
      .snapshots()
      .map((doc) => RoomModel.fromDocument(doc));
});

final userNameProvider = StreamProvider.family<String, String>((ref, uid) {
  return ref.watch(firestoreProvider)
      .collection('users')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isEmpty) return '';
        return snapshot.docs.first.data()['name'] as String? ?? '';
      });
});

/// ルーム削除前に、配下のmessagesサブコレクションを削除する
/// （Firestoreは親ドキュメントを削除してもサブコレクションは自動で消えないため）
Future<void> _deleteRoomMessages(FirebaseFirestore firestore, String roomId) async {
  final messages = await firestore
      .collection('rooms')
      .doc(roomId)
      .collection('messages')
      .get();
  for (final message in messages.docs) {
    await message.reference.delete();
  }
}

/// アカウント登録処理およびFirestoreへの初期ユーザー情報登録を行うクラス
class AuthNotifier extends AsyncNotifier<void> {
  Future<void> register(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final credential = await ref.read(authProvider).createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 非同期処理中にNotifierが破棄されてもFirestoreへの登録処理を完遂させるため、直接インスタンスから書き込む
      await ref.read(firestoreProvider).collection('users').add({
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'userId': _generateUserId(),
        'uid': credential.user!.uid,
        'name': '',
        'tutorial': {
          'roomList': false,
          'chatRoom': false,
        }
      });

      await credential.user!.sendEmailVerification();

      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  String _generateUserId() {
    const chars = 'ACDEFGHJKMNPQRTUVWXY3479';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> saveName(String name) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) return;
    final query = await ref.read(firestoreProvider).collection('users').where('uid', isEqualTo: uid).get();
    if (query.docs.isEmpty) return;
    await query.docs.first.reference.update({'name': name});
  }

  Future<void> uploadAvatar(String filePath) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if(uid == null) return;

    //storageにアップロード
    final storageRef = ref.read(storageProvider).ref().child('avatars/$uid.jpg');
    
    await storageRef.putFile(File(filePath));

    //ダウンロードURLの取得
    final url = await storageRef.getDownloadURL();

    final query = await ref.read(firestoreProvider).collection('users').where('uid', isEqualTo: uid).get();
    if (query.docs.isEmpty) return;
    await query.docs.first.reference.update({'avatarUrl': url});
  }

  /// アカウントを完全に削除する
  /// Firebase は削除前に再認証が必要なため、パスワードを受け取る
  Future<void> deleteAccount(String password) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;

    final uid   = user.uid;
    final email = user.email ?? '';

    // ① 再認証（時間が経ったセッションでは削除がブロックされる）
    //ログインから時間が経っている場合は再認証を要求
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);

    // ② Storage のアバター画像を削除
    try {
      await ref.read(storageProvider).ref('avatars/$uid.jpg').delete();
    } catch (_) {
      // アバター未設定のユーザーはスキップ
    }

    // ③ 参加中の全ルームから退会（最後の1人なら部屋ごと削除）
    final roomQuery = await ref.read(firestoreProvider)
        .collection('rooms')
        .where('members', arrayContains: uid)
        .get();

    for (final doc in roomQuery.docs) {
      await doc.reference.update({
        'members': FieldValue.arrayRemove([uid]),
      });
      final updated  = await doc.reference.get();
      final members  = List<String>.from(updated.data()?['members'] ?? []);
      if (members.isEmpty) {
        await _deleteRoomMessages(ref.read(firestoreProvider), doc.id);
        await doc.reference.delete();
      }
    }

    // ④ Firestore のユーザードキュメントを削除
    final userQuery = await ref.read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    for (final doc in userQuery.docs) {
      await doc.reference.delete();
    }

    // ⑤ Firebase Auth のアカウントを削除（最後に行う）
    await user.delete();
  }

  @override
  Future<void> build() async {}
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, void>(AuthNotifier.new);

/// ルームの新規作成およびユーザー招待ロジックを管理するクラス
class RoomNotifier extends Notifier<void> {
  Future<void> createRoom(String roomName) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if (uid == null) throw StateError('ログインユーザーが見つかりません');
    
    await ref.read(firestoreProvider).collection('rooms').add({
      'name': roomName,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'members': [uid],
      'gameState': {
        'status':           'waiting',
        'currentQuestion':  0,
        'totalQuestions':   5,
        'answers':          {},
        'scores':           {},
        'activeMembers':    [],
        'closedMembers':    [],
        'rounds':           [],
        'questionIndices':  [], // ゲーム開始時にランダム選択した問題のインデックス一覧
      },
    });
  }

  Future<void> leaveRoom(String roomId) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if(uid == null) return;

    final docRef = ref.read(firestoreProvider)
      .collection('rooms')
      .doc(roomId);
    
    await docRef.update({
      // membersから自分を削除
      'members':FieldValue.arrayRemove([uid])
    });

    // 削除後のmembersを確認
    final doc = await docRef.get();
    final data = doc.data();
    if(data == null)return;

    // membersが空になったらルームを削除
    final members = List<String>.from(data['members'] ?? []);
    if(members.isEmpty){
      await _deleteRoomMessages(ref.read(firestoreProvider), roomId);
      await docRef.delete();
    }
  }

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

  Future<void> renameRoom(String roomId,String newName)async{
    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'name':newName
    });
  }

  @override
  void build() {}
}

final roomNotifierProvider = NotifierProvider<RoomNotifier, void>(RoomNotifier.new);

/// ゲーム内のお題割り当て・投票集計・ターン遷移・勝敗判定などのゲーム進行ロジックを管理するクラス
class GameNotifier extends Notifier<void> {
  
  // チャット画面を開いた時
  // RTDBに存在を書き込み、onDisconnect().remove() を予約する。
  // → 通常終了でも task-kill でも確実に削除される。
  Future<void> joinGame(String roomId, String uid) async {
    try {
      final presenceRef = ref.read(databaseProvider)
          .ref('rooms/$roomId/activeMembers/$uid');

      // サーバーに「切断時は自動削除」を登録（task-kill対策の核心）
      await presenceRef.onDisconnect().remove();
      // 自分の存在を書き込む（onDisconnect登録の後に書くのが重要）
      await presenceRef.set(true);

      debugPrint('✅ joinGame 成功: roomId=$roomId, uid=$uid');
    } catch (e) {
      debugPrint('❌ joinGame エラー: $e');
    }
  }

  // チャット画面を正常に閉じた時
  // onDisconnect をキャンセルしてから自分で削除する。
  Future<void> leaveGame(String roomId, String uid) async {
    final presenceRef = ref.read(databaseProvider)
        .ref('rooms/$roomId/activeMembers/$uid');

    // 正常終了なので、サーバー側の自動削除予約は不要
    await presenceRef.onDisconnect().cancel();
    // 即座に削除
    await presenceRef.remove();
  }

  Future<void> startGame(String roomId, List<String> activeMembers) async {
    // kQuestionsから5問をランダムに選んでインデックスを保存する
    // こうすることでゲームごとに毎回違う問題が出題される
    final allIndices = List.generate(kQuestions.length, (i) => i)..shuffle(Random());
    final selectedIndices = allIndices.take(5).toList();

    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'gameState.status':           'playing',
      'gameState.currentQuestion':  0,
      'gameState.totalQuestions':   5,
      'gameState.answers':          {},
      'gameState.scores':           {},
      'gameState.rounds':           [],
      'gameState.closedMembers':    [],
      'gameState.activeMembers':    activeMembers, // ゲーム開始時のメンバーを記録（結果表示・スコア計算に使用）
      'gameState.questionIndices':  selectedIndices,
    });
  }

  Future<void> submitAnswer(String roomId,String uid,int answerIndex,List<String> activeMembers)async{
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    // 読み取りと書き込みを1つの不可分な操作にまとめることで、
    // 複数人が同時に回答しても「全員回答済み」の判定が正しく行われるようにする
    final allAnswered = await ref.read(firestoreProvider).runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = snapshot.data();
      if (data == null) return false;

      final gameState = Map<String, dynamic>.from(data['gameState'] ?? {});
      final answers = Map<String, dynamic>.from(gameState['answers'] ?? {});
      answers[uid] = answerIndex;

      transaction.update(docRef, {
        'gameState.answers.$uid': answerIndex,
      });

      return activeMembers.every((memberId) => answers.containsKey(memberId));
    });

    if (allAnswered) {
      await nextQuestion(roomId, activeMembers);
    }
  }

  //次の問題に進む
  Future<void> nextQuestion(String roomId,List<String> activeMembers)async{
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    //最新データの取得
    final doc = await docRef.get();
    final data = doc.data();
    if(data == null) return;

    final gameState          = data['gameState']          as Map<String, dynamic>? ?? {};
    final currentQ           = gameState['currentQuestion'] as int? ?? 0;
    final totalQ             = gameState['totalQuestions']  as int? ?? 5;
    final answersRaw         = gameState['answers']         as Map<String, dynamic>? ?? {};
    final scoresRaw          = gameState['scores']          as Map<String, dynamic>? ?? {};
    final roundsRaw          = gameState['rounds']          as List<dynamic>? ?? [];
    // startGame時に選ばれた問題インデックスの一覧を取得
    final questionIndicesRaw = gameState['questionIndices'] as List<dynamic>? ?? [];
    final questionIndices    = questionIndicesRaw.map((e) => e as int).toList();

    // インデックスが存在すればランダム選択済みの問題を、なければフォールバックとして currentQ をそのまま使う
    final actualIndex = questionIndices.isNotEmpty && currentQ < questionIndices.length
        ? questionIndices[currentQ]
        : currentQ % kQuestions.length;

    //今回の問題データを取得
    final currentQuestionData = kQuestions[actualIndex];

    //roundsに今回の回答を追加
    final newRound = {
      'question':currentQuestionData['question'],
      'choices': currentQuestionData['choices'],
      'answers':answersRaw,
    };

    final updatedRounds = [
      ...roundsRaw.map((e) => Map<String, dynamic>.from(e as Map)),
      newRound,
    ];

    // スコアを更新（2人ずつ比較して一致していたら+1）
    final updatedScores = Map<String, int>.from(
      scoresRaw.map((key, value) => MapEntry(key, value as int)),
    );

    for (int i = 0; i < activeMembers.length; i++) {
      for (int j = i + 1; j < activeMembers.length; j++) {
        final uid1 = activeMembers[i];
        final uid2 = activeMembers[j];
        final sortedUids = [uid1, uid2]..sort();
        final key = '${sortedUids[0]}_${sortedUids[1]}';

        // 同じ選択肢を選んでいたらスコア+1
        if (answersRaw[uid1] == answersRaw[uid2]) {
          updatedScores[key] = (updatedScores[key] ?? 0) + 1;
        }
      }
    }

    final isLastQuestion = currentQ + 1 >= totalQ;

    if (isLastQuestion) {
      // 5問終わったのでresultへ
      await docRef.update({
        'gameState.status':          'result',
        'gameState.rounds':          updatedRounds,
        'gameState.scores':          updatedScores,
        'gameState.answers':         {},
        'gameState.closedMembers':   [],
      });
    } else {
      // 次の問題へ
      await docRef.update({
        'gameState.currentQuestion': currentQ + 1,
        'gameState.answers':         {},
        'gameState.rounds':          updatedRounds,
        'gameState.scores':          updatedScores,
      });
    }
  }

  /// ゲーム終了処理
  /// waitingに戻してデータをリセットする
  Future<void> endGame(String roomId) async {
    await ref.read(firestoreProvider)
        .collection('rooms')
        .doc(roomId)
        .update({
          'gameState.status':          'waiting',
          'gameState.currentQuestion': 0,
          'gameState.answers':         {},
          'gameState.scores':          {},
          'gameState.rounds':          [],
          'gameState.closedMembers':   [],
        });
  }

  /// ユーザーが結果画面を閉じる処理
  /// 全員が閉じたらendGame()を呼ぶ
  Future<void> closeResult(
  String roomId,
  String uid,
  List<String> activeMembers,
) async {
  final docRef = ref.read(firestoreProvider)
      .collection('rooms')
      .doc(roomId);

  await docRef.update({
    'gameState.closedMembers': FieldValue.arrayUnion([uid]),
  });

  final doc = await docRef.get();
  final data = doc.data();
  if (data == null) return;

  final gameState     = data['gameState'] as Map<String, dynamic>? ?? {};
  final closedMembers = List<String>.from(gameState['closedMembers'] ?? []);

  final allClosed = activeMembers.every(
    (m) => closedMembers.contains(m),
  );

  if (allClosed) {
    // ゲーム結果をメッセージとして保存してから終了
    await ref.read(firestoreProvider)
        .collection('rooms')
        .doc(roomId)
        .collection('messages')
        .add({
          'type':      'game_session',
          'text':      '',
          'uid':       '',
          'email':     '',
          'rounds':    gameState['rounds']  ?? [],
          'scores':    gameState['scores']  ?? {},
          'createdAt': FieldValue.serverTimestamp(),
        });

    await endGame(roomId);
  }
}

  @override
  void build() {}
}

final gameNotifierProvider = NotifierProvider<GameNotifier, void>(GameNotifier.new);
