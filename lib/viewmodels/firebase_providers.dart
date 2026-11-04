import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// テスト時にモックへ差し替えられるようFirebaseインスタンスをDIする
final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);
final storageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);
// RTDBはタスクキル時のプレゼンス管理（onDisconnect）専用
// databaseURL は Firebase コンソール → Realtime Database の上部に表示されている URL
final databaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://bomb-chat-6da2d-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
});
