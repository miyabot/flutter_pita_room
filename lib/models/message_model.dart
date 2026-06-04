import 'package:cloud_firestore/cloud_firestore.dart';

/// [MessageModel] は Firestore における個々のチャットメッセージドキュメントを表します。
///
/// メッセージのパラメータをカプセル化することで、チャット画面でメッセージを表示する際の
/// 型安全性を保証します。
class MessageModel {
  /// このメッセージの Firestore ドキュメント ID。
  final String id;

  /// メッセージのテキスト内容。
  final String text;

  /// 送信者の Firebase Authentication UID。
  final String uid;

  /// 送信者のメールアドレス
  final String email;

  /// 名前（表示名として使用）
  final String name;

  /// メッセージが送信された日時。
  final DateTime? createdAt;

  /// メッセージの種別。'chat'=通常チャット、'game_summary'=ゲームサマリー
  final String type;

  /// game_session用：全ラウンドのデータ（name, answer, correctVotes, incorrectVotes）
  final List<Map<String, dynamic>> rounds;

  // フィールドに追加
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

  /// Firestore の [DocumentSnapshot] から [MessageModel] を生成するファクトリコンストラクタ。
  ///
  /// 安全なマッピングにより、必須フィールドの欠落や異なるタイムスタンプ型によるパースエラーを防ぎます。
  factory MessageModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw ArgumentError('Message document data cannot be null');
    }

    final timestamp = data['createdAt'] as Timestamp?;
    final scoresRaw = data['scores'] as Map<String, dynamic>? ?? {};
    final scores = scoresRaw.map(
      (key, value) => MapEntry(key, value as int),
    );

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

  /// [MessageModel] を Firestore の書き込み操作用の Map に変換します。
  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'uid': uid,
      'email': email,
      'name': name,
      'type': type,
      'rounds': rounds,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'scores': scores,
    };
  }
}
