import 'package:cloud_firestore/cloud_firestore.dart';

//ルーム内の全メッセージを削除する関数(Firestoreは親を消してもサブコレクションが残るため先に削除する)
Future<void> deleteRoomMessages(
  FirebaseFirestore firestore,
  String roomId,
) async {
  final messages = await firestore
      .collection('rooms')
      .doc(roomId)
      .collection('messages')
      .get();
  for (final message in messages.docs) {
    await message.reference.delete();
  }
}
