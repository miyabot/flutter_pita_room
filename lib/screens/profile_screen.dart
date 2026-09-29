import 'package:pita_room/providers.dart';
import 'package:pita_room/utils/app_links.dart';
import 'package:pita_room/utils/auth_error_message.dart';
import 'package:pita_room/utils/constants.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

//アバター画像のリサイズ後のサイズ
const _kAvatarImageSize = 512.0;

//アバター画像の圧縮品質(0〜100)
const _kAvatarImageQuality = 80;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  bool _isUploading = false;
  bool _isDeleting = false;
  final _nameController = TextEditingController();

  //アカウント削除の確認からパスワード再認証、削除実行までを行う関数
  Future<void> _showDeleteDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('アカウントを削除'),
        content: const Text('アカウントを削除すると、すべてのデータが失われます。\nこの操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // 再認証に必要なパスワードを確認する
    String enteredPassword = '';
    bool passwordVisible = false;
    final passwordConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('パスワードを確認'),
          content: TextField(
            obscureText: !passwordVisible,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'パスワード',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  passwordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setDialogState(() => passwordVisible = !passwordVisible),
              ),
            ),
            onChanged: (value) => enteredPassword = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ),
    );
    if (passwordConfirmed != true || enteredPassword.isEmpty) return;
    if (!mounted) return;

    setState(() => _isDeleting = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .deleteAccount(enteredPassword);
      // currentUserProviderがnullになって「データなし」の画面が一瞬映る前にルートへ戻す
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // invalid-credential はログイン画面用のメッセージだが、
      // ここではパスワードしか入力していないので専用メッセージに上書き
      final message =
          (e.code == 'invalid-credential' || e.code == 'wrong-password')
          ? 'パスワードが間違っています'
          : authErrorMessage(e.code);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  //プロフィール画面のUIを構築する関数
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: ref
          .watch(currentUserProvider)
          .when(
            data: (userModel) {
              if (userModel == null) {
                return const Center(child: Text('データがありません'));
              }
              return SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // アバター（グラデーション枠）
                    Stack(
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [Color(0xFFE91E8C), Color(0xFFFF80AB)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: CircleAvatar(
                            radius: 48,
                            backgroundColor: const Color(0xFFFCE4EC),
                            backgroundImage: userModel.avatarUrl.isNotEmpty
                                ? NetworkImage(userModel.avatarUrl)
                                : null,
                            child: _isUploading
                                ? const CircularProgressIndicator(
                                    color: Color(0xFFE91E8C),
                                    strokeWidth: 2,
                                  )
                                : userModel.avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: 52,
                                    color: Color(0xFF9E7B8A),
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () async {
                              final picker = ImagePicker();
                              final image = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: _kAvatarImageSize,
                                maxHeight: _kAvatarImageSize,
                                imageQuality: _kAvatarImageQuality,
                              );
                              if (image == null) return;
                              setState(() => _isUploading = true);
                              await ref
                                  .read(authNotifierProvider.notifier)
                                  .uploadAvatar(image.path);
                              if (mounted) setState(() => _isUploading = false);
                            },
                            child: Container(
                              padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Color(0xFFE91E8C),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Color(0xFFAD1461),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // 名前 + 編集
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _isEditing
                            ? SizedBox(
                                width: 200,
                                child: TextField(
                                  maxLength: kDisplayNameMaxLength,
                                  controller: _nameController,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              )
                            : Text(
                                userModel.name,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D1B33),
                                ),
                              ),
                        IconButton(
                          onPressed: () async {
                            if (_isEditing) {
                              await ref
                                  .read(authNotifierProvider.notifier)
                                  .saveName(_nameController.text.trim());
                              setState(() => _isEditing = false);
                            } else {
                              _nameController.text = userModel.name;
                              setState(() => _isEditing = true);
                            }
                          },
                          icon: Icon(
                            _isEditing ? Icons.check_circle : Icons.edit,
                            color: const Color(0xFFE91E8C),
                          ),
                        ),
                      ],
                    ),

                    Text(
                      userModel.email,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9E7B8A),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // 招待IDカード
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFFFCDD2),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33E91E8C),
                            offset: Offset(3, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '招待ID',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF9E7B8A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                userModel.userId,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 4,
                                  color: Color(0xFFE91E8C),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'IDをコピー',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: userModel.userId),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('IDをコピーしました')),
                              );
                            },
                            icon: const Icon(
                              Icons.copy,
                              color: Color(0xFF9E7B8A),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // プライバシーポリシー・利用規約
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () =>
                              launchUrl(Uri.parse(kPrivacyPolicyUrl)),
                          child: const Text(
                            'プライバシーポリシー',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFAD5D7A),
                            ),
                          ),
                        ),
                        const Text(
                          '・',
                          style: TextStyle(color: Color(0xFFAD5D7A)),
                        ),
                        TextButton(
                          onPressed: () =>
                              launchUrl(Uri.parse(kTermsOfServiceUrl)),
                          child: const Text(
                            '利用規約',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFAD5D7A),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // アカウント削除ボタン
                    if (_isDeleting)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.red),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _showDeleteDialog,
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'アカウントを削除',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFFE91E8C)),
            ),
            error: (error, stack) => Center(child: Text('エラーが発生しました: $error')),
          ),
    );
  }
}
