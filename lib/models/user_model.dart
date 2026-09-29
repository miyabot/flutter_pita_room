import 'package:cloud_firestore/cloud_firestore.dart';

// Firestoreの users ドキュメントに対応するモデル
class UserModel {
  final String uid;
  final String email;

  // ユーザー招待に使う、アプリ独自のランダムな6文字ID
  final String userId;
  final DateTime? createdAt;
  final String name;
  final String avatarUrl;

  const UserModel({
    required this.uid,
    required this.email,
    required this.userId,
    this.createdAt,
    required this.name,
    required this.avatarUrl,
  });

  //FirestoreのドキュメントからUserModelを作る関数
  factory UserModel.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      throw ArgumentError('Document data cannot be null');
    }

    final timestamp = data['createdAt'] as Timestamp?;

    return UserModel(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      createdAt: timestamp?.toDate(),
      name: data['name'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String? ?? '',
    );
  }

  //Firestore書き込み用のMapに変換する関数
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'userId': userId,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'name': name,
      'avatarUrl': avatarUrl,
    };
  }
}
