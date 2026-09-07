import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:musicality/core/globals.dart';
import 'package:musicality/main.dart';

class AccountProfileHeader extends StatelessWidget {
  final List<Color> dynamicGradientColors;
  final void Function(String message, {bool isError}) showSnackBar;

  const AccountProfileHeader({
    super.key,
    required this.dynamicGradientColors,
    required this.showSnackBar,
  });

  Future<void> _showAuth(BuildContext context, bool isLogin) async {
    await showAuthDialog(
      context: context,
      isLogin: isLogin,
      primaryColor: dynamicGradientColors[0],
      showSnackBar: showSnackBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // --- AVATAR DYNAMIQUE EN TEMPS RÉEL ---
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            final user = authSnapshot.data;

            return ValueListenableBuilder<String?>(
              valueListenable: userProfileImageNotifier,
              builder: (context, imagePath, child) {
                // 1. On récupère les infos
                final hasGoogleImage = user != null && user.photoURL != null;
                final hasLocalImage =
                    imagePath != null &&
                    imagePath.isNotEmpty &&
                    File(imagePath).existsSync();

                final cachedGoogleAvatar = File(
                  '$globalDocumentPath/cached_google_avatar.jpg',
                );
                final hasCachedGoogle = cachedGoogleAvatar.existsSync();

                if (hasGoogleImage) {
                  cacheGoogleAvatar(user.photoURL!);
                }

                // 2. Priorité: Locale > Google Cachée > Google Réseau > Défaut
                Widget avatarWidget;
                if (hasLocalImage) {
                  avatarWidget = Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                  );
                } else if (hasCachedGoogle) {
                  avatarWidget = Image.file(
                    cachedGoogleAvatar,
                    fit: BoxFit.cover,
                  );
                } else if (hasGoogleImage) {
                  avatarWidget = Image.network(
                    user.photoURL!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        CupertinoIcons.person_fill,
                        color: Colors.white54,
                        size: 60,
                      );
                    },
                  );
                } else {
                  avatarWidget = const Icon(
                    CupertinoIcons.person_fill,
                    color: Colors.white54,
                    size: 60,
                  );
                }

                return GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final xfile = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (xfile != null) {
                      userProfileImageNotifier.value = xfile.path;
                    }
                  },
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.1),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: dynamicGradientColors[0]
                                  .withValues(alpha: 0.3),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: ClipOval(child: avatarWidget),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: dynamicGradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          CupertinoIcons.camera_fill,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),

        const SizedBox(height: 16),

        // --- SECTION FIREBASE : AUTHENTIFICATION ---
        StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            final user = snapshot.data;
            final isLoggedIn = user != null;

            return Column(
              children: [
                Text(
                  isLoggedIn
                      ? (user.email ?? "Utilisateur Connecté")
                      : "Utilisateur Local",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    isLoggedIn
                        ? "Synchronisation Cloud Activée"
                        : "Données stockées uniquement sur cet appareil",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isLoggedIn
                          ? dynamicGradientColors[0]
                          : Colors.white54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: isLoggedIn
                        ? CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 24,
                            ),
                            color: Colors.white.withValues(alpha: 0.1),
                            onPressed: () => FirebaseAuth.instance.signOut(),
                            child: const Text(
                              "Se déconnecter",
                              style: TextStyle(
                                color: Color(0xFFFF5252),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  color: Colors.white.withValues(alpha: 0.1),
                                  onPressed: () => _showAuth(context, false),
                                  child: const Text(
                                    "Créer un compte",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  color: dynamicGradientColors[0],
                                  onPressed: () => _showAuth(context, true),
                                  child: const Text(
                                    "Connexion",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
