//FirebaseAuthのエラーコードを日本語メッセージに変換する関数
String authErrorMessage(String code) {
  switch (code) {
    case 'user-not-found':
      return 'このメールアドレスは登録されていません';
    case 'wrong-password':
      return 'パスワードが間違っています';
    case 'invalid-email':
      return 'メールアドレスの形式が正しくありません';
    case 'user-disabled':
      return 'このアカウントは無効になっています';
    case 'too-many-requests':
      return 'ログイン試行回数が多すぎます。しばらくお待ちください';
    case 'email-already-in-use':
      return 'このメールアドレスはすでに使用されています';
    case 'weak-password':
      return 'パスワードは6文字以上で設定してください';
    case 'network-request-failed':
      return 'ネットワークエラーが発生しました。通信環境を確認してください';
    case 'invalid-credential':
      return 'メールアドレスまたはパスワードが間違っています';
    default:
      return 'エラーが発生しました。もう一度お試しください';
  }
}
