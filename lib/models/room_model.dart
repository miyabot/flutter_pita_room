import 'package:cloud_firestore/cloud_firestore.dart';

/// [RoomModel] は Cloud Firestore におけるチャットルームドキュメントを表し、その中で行われるゲームのアクティブな状態を含みます。
///
/// ルーム詳細とゲームの状態を専用のモデルにカプセル化することで、UI や状態コントローラが
/// Firestore の Map 構造に直接依存することなくルームを操作できるようにします。
class RoomModel {
  /// このルームの Firestore ドキュメント ID。
  final String id;
  
  /// ルームの表示名。
  final String name;

  /// ルームが作成された日時。
  final DateTime? createdAt;

  /// ルームを作成したユーザーの Firebase Authentication UID。
  final String createdBy;

  /// 現在このルームに参加しているメンバーの UID リスト。
  final List<String> members;

  /// このルームに関連付けられたゲームの現在の状態。
  final GameState gameState;

  const RoomModel({
    required this.id,
    required this.name,
    this.createdAt,
    required this.createdBy,
    required this.members,
    required this.gameState,
  });

  /// Firestore の [DocumentSnapshot] から [RoomModel] を生成するファクトリコンストラクタ。
  ///
  /// このコンストラクタはバリデーションを行い、型安全性を確保します。
  factory RoomModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw ArgumentError('Room document data cannot be null');
    }

    final timestamp = data['createdAt'] as Timestamp?;
    final membersRaw = data['members'] as List<dynamic>? ?? [];
    final membersList = membersRaw.map((e) => e.toString()).toList();

    return RoomModel(
      id: doc.id,
      name: data['name'] as String? ?? '',
      createdAt: timestamp?.toDate(),
      createdBy: data['createdBy'] as String? ?? '',
      members: membersList,
      gameState: GameState.fromMap(data['gameState'] as Map<String, dynamic>? ?? {}),
    );
  }

  /// データベースへの書き込み用に、[RoomModel] を Map 表現に逆変換します。
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'members': members,
      'gameState': gameState.toMap(),
    };
  }
}

/// [GameState] はルーム内における「ボムゲーム（爆弾ゲーム）」の現在の進行状況を表します。
/// [GameState] はルーム内における共通点探しゲームの現在の進行状況を表します。
class GameState {
  /// ゲームのステータス
  /// 'waiting'（待機中）/ 'playing'（ゲーム中）/ 'result'（結果発表）
  final String status;

  /// 現在何問目か（0〜4）
  final int currentQuestion;

  /// 全部で何問か（5固定）
  final int totalQuestions;

  /// 各ユーザーの回答を記録するMap
  /// キー：uid　値：選択肢のインデックス（0〜3）
  /// 全員が回答したら次の問題へ進む
  final Map<String, int> answers;

  /// ユーザー間のマッチングスコアを記録するMap
  /// キー：'uid001_uid002'　値：一致した回数
  final Map<String, int> scores;

  /// 今チャット画面を開いているメンバーのUIDリスト
  /// ゲームの参加者はこのリストを使う
  final List<String> activeMembers;

  /// 結果画面を閉じたメンバーのUIDリスト
  /// 全員が閉じたらendGame()を呼ぶ
  final List<String> closedMembers;

  /// 各問題の回答履歴
  /// ゲーム終了後も確認できるように保存する
  /// 各要素の構造：
  /// {
  ///   'question': 'お題のテキスト',
  ///   'choices':  ['選択肢1', '選択肢2', '選択肢3', '選択肢4'],
  ///   'answers':  {'uid001': 0, 'uid002': 2, ...}
  /// }
  final List<Map<String, dynamic>> rounds;

  const GameState({
    required this.status,
    required this.currentQuestion,
    required this.totalQuestions,
    required this.answers,
    required this.scores,
    required this.activeMembers,
    required this.closedMembers,
    this.rounds = const [],
  });

  /// Firestoreから取得したMapからGameStateを生成するファクトリコンストラクタ
  factory GameState.fromMap(Map<String, dynamic> map) {
    // activeMembers: List<dynamic> → List<String>に変換
    final activeRaw = map['activeMembers'] as List<dynamic>? ?? [];
    final activeList = activeRaw.map((e) => e.toString()).toList();

    // closedMembers: List<dynamic> → List<String>に変換
    final closedRaw = map['closedMembers'] as List<dynamic>? ?? [];
    final closedList = closedRaw.map((e) => e.toString()).toList();

    // answers: Map<String, dynamic> → Map<String, int>に変換
    final answersRaw = map['answers'] as Map<String, dynamic>? ?? {};
    final answers = answersRaw.map(
      (key, value) => MapEntry(key, value as int),
    );

    // scores: Map<String, dynamic> → Map<String, int>に変換
    final scoresRaw = map['scores'] as Map<String, dynamic>? ?? {};
    final scores = scoresRaw.map(
      (key, value) => MapEntry(key, value as int),
    );

    // rounds: List<dynamic> → List<Map<String, dynamic>>に変換
    final roundsList = (map['rounds'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return GameState(
      status:          map['status']          as String? ?? 'waiting',
      currentQuestion: map['currentQuestion'] as int?    ?? 0,
      totalQuestions:  map['totalQuestions']  as int?    ?? 5,
      answers:         answers,
      scores:          scores,
      activeMembers:   activeList,
      closedMembers:   closedList,
      rounds:          roundsList,
    );
  }

  /// GameStateをFirestore書き込み用のMapに変換する
  Map<String, dynamic> toMap() {
    return {
      'status':          status,
      'currentQuestion': currentQuestion,
      'totalQuestions':  totalQuestions,
      'answers':         answers,
      'scores':          scores,
      'activeMembers':   activeMembers,
      'closedMembers':   closedMembers,
      'rounds':          rounds,
    };
  }
}
