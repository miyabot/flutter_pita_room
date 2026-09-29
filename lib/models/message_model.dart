import 'package:cloud_firestore/cloud_firestore.dart';

// Firestoreの rooms/{roomId}/messages ドキュメントに対応するモデル
class MessageModel {
  final String id;
  final String text;
  final String uid;
  final String email;
  final String name;
  final DateTime? createdAt;

  // 'chat'(通常チャット) または 'game_session'(ゲーム結果)
  final String type;

  // type: 'game_session' の場合のみ使用する各問題の回答履歴
  final List<Map<String, dynamic>> rounds;
  final Map<String, int> scores;

  const MessageModel({
    required this.id,
    required this.text,
    required this.uid,
    required this.email,
    required this.name,
    this.createdAt,
    this.type = 'chat',
    this.rounds = const [],
    required this.scores,
  });

  //FirestoreのドキュメントからMessageModelを作る関数
  factory MessageModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw ArgumentError('Message document data cannot be null');
    }

    final timestamp = data['createdAt'] as Timestamp?;
    final scoresRaw = data['scores'] as Map<String, dynamic>? ?? {};
    final scores = scoresRaw.map((key, value) => MapEntry(key, value as int));

    return MessageModel(
      id: doc.id,
      text: data['text'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
      createdAt: timestamp?.toDate(),
      type: data['type'] as String? ?? 'chat',
      rounds: (data['rounds'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      scores: scores,
    );
  }

  //Firestore書き込み用のMapに変換する関数
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'uid': uid,
      'email': email,
      'name': name,
      'type': type,
      'rounds': rounds,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'scores': scores,
    };
  }
}
