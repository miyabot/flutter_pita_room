import 'dart:io';
import 'dart:math';

import 'package:bomb_chat/models/user_model.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'models/room_model.dart';
import 'models/message_model.dart';

// テスト時のモック化やテスト容易性を高めるDI用プロバイダー
final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final storageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authProvider).authStateChanges();
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
  return ref.watch(firestoreProvider).
      collection('users').
      where('uid',isEqualTo: uid).
      snapshots().
      map((snapshot){
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
      });

      state = const AsyncValue.data(null);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  String _generateUserId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> saveName(String name)async{
    final uid = ref.read(authProvider).currentUser?.uid;
    if(uid == null)return;

    final query = await ref.read(firestoreProvider).collection('users').where('uid',isEqualTo: uid).get();
    if (query.docs.isEmpty) return;
    await ref.read(firestoreProvider)
      .collection('users')
      .doc(query.docs.first.id)
      .update({'name': name});
  }

  Future<void> uploadAvatar(String filePath) async {
    final uid = ref.read(authProvider).currentUser?.uid;
    if(uid == null) return;

    //storageにアップロード
    final storageRef = ref.read(storageProvider).ref().child('avatars/$uid.jpg');
    
    await storageRef.putFile(File(filePath));

    //ダウンロードURLの取得
    final url = await storageRef.getDownloadURL();

    final query = await ref.read(firestoreProvider).collection('users').where('uid',isEqualTo: uid).get();
    if(query.docs.isEmpty) return;
    await ref.read(firestoreProvider).collection('users').doc(query.docs.first.id).update({'avatarUrl': url});
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
        'status':          'waiting',
        'currentQuestion': 0,
        'totalQuestions':  5,
        'answers':         {},
        'scores':          {},
        'activeMembers':   [],
        'closedMembers':   [],
        'rounds':          [],
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


/// お題と選択肢のプリセット
const List<Map<String, dynamic>> kQuestions = [
  {
    'question': '好きな食べ物は？',
    'choices': ['ラーメン', '寿司', '焼肉', 'カレー'],
  },
  {
    'question': '休日の過ごし方は？',
    'choices': ['家でゴロゴロ', '外出・買い物', 'スポーツ', '旅行'],
  },
  {
    'question': '好きな季節は？',
    'choices': ['春', '夏', '秋', '冬'],
  },
  {
    'question': 'ストレス発散方法は？',
    'choices': ['食べる', '寝る', '運動する', '話す'],
  },
  {
    'question': '朝型・夜型どっち？',
    'choices': ['完全朝型', 'どちらかといえば朝型', 'どちらかといえば夜型', '完全夜型'],
  },
];

/// ゲーム内のお題割り当て・投票集計・ターン遷移・勝敗判定などのゲーム進行ロジックを管理するクラス
class GameNotifier extends Notifier<void> {
  
  //チャット画面を開いた時
  Future<void> joinGame(String roomId,String uid)async{
    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'gameState.activeMembers': FieldValue.arrayUnion([uid]),
    });
  }

  //チャット画面を閉じた時
  Future<void> leaveGame(String roomId,String uid)async{
    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'gameState.activeMembers': FieldValue.arrayRemove([uid]),
    });
  }

  Future<void> startGame(String roomId) async {
    await ref.read(firestoreProvider).collection('rooms').doc(roomId).update({
      'gameState.status':          'playing',
          'gameState.currentQuestion': 0,
          'gameState.totalQuestions':  5,
          'gameState.answers':         {},
          'gameState.scores':          {},
          'gameState.rounds':          [],
          'gameState.closedMembers':   [],
    });
  }

  Future<void> submitAnswer(String roomId,String uid,int answerIndex,List<String> activeMembers)async{
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    //自分の回答を保存
    await docRef.update({
      'gameState.answers.$uid':answerIndex,
    });

    //最新データを取得して全員が回答したか確認
    final doc = await docRef.get();
    final data = doc.data();
    if(data == null)return;

    final gameState = data['gameState'] as Map<String,dynamic>? ?? {};
    final answers = gameState['answers'] as Map<String,dynamic>? ?? {};

    //activeMembers全員が回答したか確認
    final allAnswered = activeMembers.every(
      (memberId) => answers.containsKey(memberId),
    );

    if(allAnswered){
      await nextQuestion(roomId,activeMembers);
    }
  }

  //次の問題に進む
  Future<void> nextQuestion(String roomId,List<String> activeMembers)async{
    final docRef = ref.read(firestoreProvider).collection('rooms').doc(roomId);

    //最新データの取得
    final doc = await docRef.get();
    final data = doc.data();
    if(data == null) return;

    final gameState  = data['gameState']  as Map<String, dynamic>? ?? {};
    final currentQ   = gameState['currentQuestion'] as int? ?? 0;
    final totalQ     = gameState['totalQuestions']  as int? ?? 5;
    final answersRaw = gameState['answers'] as Map<String, dynamic>? ?? {};
    final scoresRaw  = gameState['scores']  as Map<String, dynamic>? ?? {};
    final roundsRaw  = gameState['rounds']  as List<dynamic>? ?? [];

    //今回の問題データを取得
    final currentQuestionData = kQuestions[currentQ];

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
