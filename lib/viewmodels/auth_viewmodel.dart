import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../utils/constants.dart';
import '../utils/firestore_helpers.dart';
import 'firebase_providers.dart';

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

class AuthNotifier extends AsyncNotifier<void> {
  //ログイン中ユーザーのuidを返す関数(未ログインならnull)
  String? get currentUid => ref.read(authProvider).currentUser?.uid;

  //ログイン中ユーザーのメールアドレスを返す関数
  String get currentEmail => ref.read(authProvider).currentUser?.email ?? '';

  //メールアドレスとパスワードでログインする関数
  Future<void> signIn(String email, String password) async {
    await ref
        .read(authProvider)
        .signInWithEmailAndPassword(email: email, password: password);
  }

  //ログアウトする関数
  Future<void> signOut() async {
    await ref.read(authProvider).signOut();
  }

  //パスワードリセットメールを送信する関数
  Future<void> sendPasswordReset(String email) async {
    await ref.read(authProvider).sendPasswordResetEmail(email: email);
  }

  //メール確認済みかをサーバーから再取得して返す関数
  Future<bool> refreshEmailVerified() async {
    await ref.read(authProvider).currentUser?.reload();
    //画面更新のきっかけ（トークン）を作る
    await ref.read(authProvider).currentUser?.getIdToken(true);
    return ref.read(authProvider).currentUser?.emailVerified ?? false;
  }

  //確認メールを再送信する関数
  Future<void> resendVerificationEmail() async {
    await ref.read(authProvider).currentUser?.sendEmailVerification();
  }

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

  //チュートリアルを表示済みかを取得する関数(未ログインならnull)
  Future<bool?> loadTutorialDone(String key) async {
    final uid = currentUid;
    if (uid == null) return null;
    final query = await ref
        .read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    final tutorialMap = query.docs.isEmpty
        ? null
        : query.docs.first.data()['tutorial'];
    return tutorialMap is Map && tutorialMap[key] == true;
  }

  //チュートリアルを表示済みとして保存する関数
  Future<void> markTutorialDone(String key) async {
    final uid = currentUid;
    if (uid == null) return;
    final query = await ref
        .read(firestoreProvider)
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();
    if (query.docs.isEmpty) return;
    await query.docs.first.reference.update({'tutorial.$key': true});
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
        await deleteRoomMessages(ref.read(firestoreProvider), doc.id);
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
