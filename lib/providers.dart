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


/// お題と選択肢のプリセット（全25問・5カテゴリ）
/// ゲーム開始時にランダムで5問選ばれる
const List<Map<String, dynamic>> kQuestions = [
  // 🍽️ 食べ物カテゴリ
  {
    'category': '食べ物',
    'question': '好きな食べ物は？',
    'choices': ['ラーメン', '寿司', '焼肉', 'カレー'],
  },
  {
    'category': '食べ物',
    'question': '好きなデザートは？',
    'choices': ['ケーキ', 'アイス', 'チョコ', '和菓子'],
  },
  {
    'category': '食べ物',
    'question': '朝ごはんは食べる？',
    'choices': ['毎日食べる', 'たまに食べる', 'ほぼ食べない', '食べたい気持ちはある'],
  },
  {
    'category': '食べ物',
    'question': '好きな飲み物は？',
    'choices': ['コーヒー', 'お茶', 'ジュース', '水'],
  },
  {
    'category': '食べ物',
    'question': '辛い食べ物は好き？',
    'choices': ['大好き', 'まあ好き', 'あまり好きじゃない', '無理'],
  },

  // 🎮 趣味・娯楽カテゴリ
  {
    'category': '趣味',
    'question': '休日の過ごし方は？',
    'choices': ['家でゴロゴロ', '外出・買い物', 'スポーツ', '旅行'],
  },
  {
    'category': '趣味',
    'question': '好きな映画のジャンルは？',
    'choices': ['アクション', 'ラブコメ', 'ホラー', 'SF'],
  },
  {
    'category': '趣味',
    'question': '好きな音楽のジャンルは？',
    'choices': ['J-POP', 'アニソン', 'R&B / Hip-hop', '洋楽'],
  },
  {
    'category': '趣味',
    'question': 'ゲームはする？',
    'choices': ['毎日する', 'たまにする', 'スマホゲームだけ', 'しない'],
  },
  {
    'category': '趣味',
    'question': '旅行するなら？',
    'choices': ['国内・自然', '国内・都市', '海外・アジア', '海外・欧米'],
  },

  // 💡 価値観カテゴリ
  {
    'category': '価値観',
    'question': '朝型・夜型どっち？',
    'choices': ['完全朝型', 'どちらかといえば朝型', 'どちらかといえば夜型', '完全夜型'],
  },
  {
    'category': '価値観',
    'question': 'ストレス発散方法は？',
    'choices': ['食べる', '寝る', '運動する', '誰かと話す'],
  },
  {
    'category': '価値観',
    'question': '友達は多い方がいい？',
    'choices': ['多い方がいい', 'ほどほどでいい', '少数精鋭派', '一人も好き'],
  },
  {
    'category': '価値観',
    'question': '計画的？行き当たりばったり？',
    'choices': ['きっちり計画派', 'ある程度計画', 'なんとなく計画', '完全ノープラン'],
  },
  {
    'category': '価値観',
    'question': 'お金の使い方は？',
    'choices': ['貯金最優先', 'バランス重視', '経験に使う', '欲しいものに使う'],
  },

  // 🌆 日常カテゴリ
  {
    'category': '日常',
    'question': 'SNSをよく使う？',
    'choices': ['ほぼ毎日', 'たまに見る', '投稿専門', 'ほぼ使わない'],
  },
  {
    'category': '日常',
    'question': 'お風呂は朝？夜？',
    'choices': ['朝シャワー派', '夜お風呂派', '両方入る', 'その日による'],
  },
  {
    'category': '日常',
    'question': '買い物はどこで？',
    'choices': ['ネット通販派', '実店舗派', '両方使う', 'なるべく買わない'],
  },
  {
    'category': '日常',
    'question': '部屋の片づけは？',
    'choices': ['いつもきれい', 'まあきれい', 'やや散らかり気味', 'かなり散らかってる'],
  },
  {
    'category': '日常',
    'question': '連絡の頻度は？',
    'choices': ['こまめに連絡したい', '必要な時だけでいい', 'ゆっくり返す派', '既読スルーしがち'],
  },

  // 🌈 もしもカテゴリ
  {
    'category': 'もしも',
    'question': '好きな季節は？',
    'choices': ['春', '夏', '秋', '冬'],
  },
  {
    'category': 'もしも',
    'question': '無人島に1つだけ持っていくなら？',
    'choices': ['スマホ', 'ナイフ', '本', '音楽プレイヤー'],
  },
  {
    'category': 'もしも',
    'question': '1日だけ有名人になれるなら？',
    'choices': ['俳優・芸能人', 'スポーツ選手', 'ミュージシャン', '実業家'],
  },
  {
    'category': 'もしも',
    'question': '自由な時間が1週間できたら？',
    'choices': ['旅行三昧', '趣味に没頭', '勉強・スキルアップ', 'ひたすら休む'],
  },
  {
    'category': 'もしも',
    'question': '超能力が使えるなら？',
    'choices': ['テレパシー', '瞬間移動', '時間を止める', '空を飛ぶ'],
  },
];

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

  Future<void> startGame(String roomId) async {
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
      'gameState.questionIndices':  selectedIndices, // 今ゲームで使う5問のインデックス
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
