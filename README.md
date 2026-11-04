# lib ディレクトリ構成

このアプリ(ぴたルム)は Flutter + Riverpod + Firebase(Auth / Firestore / Realtime Database / Storage)構成。
各ファイルの役割を一覧にまとめたもの。

```
lib/
├── main.dart                 アプリのエントリーポイント
├── firebase_options.dart     FlutterFire CLIが生成したFirebase設定(自動生成・編集不要)
├── data/
│   └── questions.dart        ゲームの出題データ(質問と4択の一覧)、1ゲームの出題数などの定数
├── models/
│   ├── user_model.dart       Firestore `users` ドキュメントのモデル
│   ├── room_model.dart       Firestore `rooms` ドキュメントとゲーム進行状態(GameState)のモデル
│   └── message_model.dart    Firestore `rooms/{id}/messages` ドキュメントのモデル
├── viewmodels/
│   ├── firebase_providers.dart  Firebase各サービス(Auth / Firestore / Storage / RTDB)のDI用プロバイダー
│   ├── auth_viewmodel.dart      ログイン状態・プロフィールの購読と、AuthNotifier(認証・プロフィール更新・チュートリアル状態)
│   ├── room_viewmodel.dart      ルーム一覧・ルーム状態の購読と、RoomNotifier(作成・退会・招待・名前変更)
│   └── chat_viewmodel.dart      メッセージ・在室メンバーの購読と、ChatNotifier(送信)・GameNotifier(ゲーム進行)
├── utils/
│   ├── app_links.dart          プライバシーポリシー・利用規約のURL定数
│   ├── auth_error_message.dart FirebaseAuthのエラーコードを日本語メッセージに変換
│   ├── constants.dart          表示名の文字数上限・招待IDの桁数など、複数画面で共有する定数
│   └── firestore_helpers.dart  複数のViewModelから使うFirestore操作(ルーム内メッセージの一括削除)
└── screens/
    ├── login_screen.dart            ログイン画面
    ├── register_screen.dart         新規登録画面
    ├── email_verification_screen.dart メール認証待ち画面
    ├── profile_setup_screen.dart    初回ログイン時の表示名設定画面
    ├── profile_screen.dart          プロフィール画面(アバター/名前編集、招待ID表示、アカウント削除)
    ├── room_list_screen.dart        参加中のルーム一覧画面(初回チュートリアル表示を含む)
    ├── create_room_screen.dart      ルーム作成画面
    ├── invite_screen.dart           招待IDでユーザーをルームに追加する画面
    └── chat_screen.dart             チャット/ゲーム画面本体
```

## 各ファイルの補足

### main.dart
Firebase初期化、アプリ全体のテーマ定義、認証状態に応じた初期画面の出し分け(未ログイン→ログイン画面、メール未確認→確認画面、名前未設定→プロフィール設定画面、それ以外→ルーム一覧)を行う。

### 構成の考え方(MVVM)
- Model: `models/`(Firestoreのデータの形)
- View: `screens/`(表示と入力の受け取りだけ。FirebaseやFirestoreには直接触れず、ViewModelの関数を呼ぶ)
- ViewModel: `viewmodels/`(データの購読と、読み書きなどの処理)

### viewmodels/
- `firebase_providers.dart`: `authProvider` / `firestoreProvider` / `storageProvider` / `databaseProvider`
- `auth_viewmodel.dart`: `authStateProvider` / `currentUserProvider` などの購読と、`AuthNotifier`(ログイン・ログアウト・会員登録・メール確認・プロフィール更新・チュートリアル状態・アカウント削除)
- `room_viewmodel.dart`: `roomsProvider` / `currentRoomStateProvider` の購読と、`RoomNotifier`(ルームの作成・退会・招待・名前変更)
- `chat_viewmodel.dart`: `messagesProvider` / `activeMembersProvider` の購読と、`ChatNotifier`(メッセージ送信)、`GameNotifier`(ゲームの開始・回答受付・出題進行・結果集計・在室プレゼンス管理)

### models/room_model.dart
`RoomModel` がルーム自体の情報、内部の `GameState` がゲームの進行状況(お題の進み具合、回答、スコア、在室メンバーなど)を保持する。

### screens/chat_screen.dart
このアプリで最も大きい画面。ルームの状態(`waiting` / `playing` / `result`)によって、待機中のチャット・出題パネル・結果発表パネルを切り替えて表示する。`build()`本体は状態分岐のみを行い、実際の各パーツの組み立ては `_buildAppBar` / `_buildQuestionPanel` / `_buildChatList` / `_buildGameSessionCard` / `_buildChatBubble` / `_buildResultPanel` / `_buildMessageInputBar` に分割している。
