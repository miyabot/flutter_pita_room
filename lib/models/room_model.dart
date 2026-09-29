import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/questions.dart';

// Firestoreの rooms ドキュメントに対応するモデル
class RoomModel {
  final String id;
  final String name;
  final DateTime? createdAt;
  final String createdBy;
  final List<String> members;
  final GameState gameState;

  const RoomModel({
    required this.id,
    required this.name,
    this.createdAt,
    required this.createdBy,
    required this.members,
    required this.gameState,
  });

  //FirestoreのドキュメントからRoomModelを作る関数
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
      gameState: GameState.fromMap(
        data['gameState'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  //Firestore書き込み用のMapに変換する関数
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'members': members,
      'gameState': gameState.toMap(),
    };
  }
}

// ルーム内で行われる共通点探しゲームの進行状況
class GameState {
  // 'waiting' / 'playing' / 'result'
  final String status;

  // 現在何問目か(0〜4)
  final int currentQuestion;
  final int totalQuestions;

  // キー:uid、値:選択した選択肢のインデックス
  final Map<String, int> answers;

  // キー:'uid1_uid2'(ソート済み)、値:回答が一致した回数
  final Map<String, int> scores;

  // 現在チャット画面を開いているメンバーのUID(ゲーム参加者)
  final List<String> activeMembers;

  // 結果画面を閉じたメンバーのUID。全員分揃うとendGame()が呼ばれる
  final List<String> closedMembers;

  // 各問題の回答履歴: {'question', 'choices', 'answers': {uid: index}}
  final List<Map<String, dynamic>> rounds;

  // startGame時にkQuestionsからランダム選択した問題インデックス
  final List<int> questionIndices;

  const GameState({
    required this.status,
    required this.currentQuestion,
    required this.totalQuestions,
    required this.answers,
    required this.scores,
    required this.activeMembers,
    required this.closedMembers,
    this.rounds = const [],
    this.questionIndices = const [],
  });

  //FirestoreのMapからGameStateを作る関数
  factory GameState.fromMap(Map<String, dynamic> map) {
    final activeRaw = map['activeMembers'] as List<dynamic>? ?? [];
    final activeList = activeRaw.map((e) => e.toString()).toList();

    final closedRaw = map['closedMembers'] as List<dynamic>? ?? [];
    final closedList = closedRaw.map((e) => e.toString()).toList();

    final answersRaw = map['answers'] as Map<String, dynamic>? ?? {};
    final answers = answersRaw.map((key, value) => MapEntry(key, value as int));

    final scoresRaw = map['scores'] as Map<String, dynamic>? ?? {};
    final scores = scoresRaw.map((key, value) => MapEntry(key, value as int));

    final roundsList = (map['rounds'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final questionIndicesList = (map['questionIndices'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toList();

    return GameState(
      status: map['status'] as String? ?? 'waiting',
      currentQuestion: map['currentQuestion'] as int? ?? 0,
      totalQuestions: map['totalQuestions'] as int? ?? kQuestionsPerGame,
      answers: answers,
      scores: scores,
      activeMembers: activeList,
      closedMembers: closedList,
      rounds: roundsList,
      questionIndices: questionIndicesList,
    );
  }

  //Firestore書き込み用のMapに変換する関数
  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'currentQuestion': currentQuestion,
      'totalQuestions': totalQuestions,
      'answers': answers,
      'scores': scores,
      'activeMembers': activeMembers,
      'closedMembers': closedMembers,
      'rounds': rounds,
      'questionIndices': questionIndices,
    };
  }
}
