import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/questions.dart';
import '../models/room_model.dart';
import '../utils/firestore_helpers.dart';
import 'auth_viewmodel.dart';
import 'firebase_providers.dart';

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
      await deleteRoomMessages(ref.read(firestoreProvider), roomId);
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
