import 'package:musicality/core/globals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:musicality/main.dart';

class AccountPageView extends StatefulWidget {
  final List<Color> dynamicGradientColors;

  const AccountPageView({super.key, required this.dynamicGradientColors});

  @override
  State<AccountPageView> createState() => _AccountPageViewState();
}

class _AccountPageViewState extends State<AccountPageView> {
  int _cacheSizeBytes = 0;
  int _downloadedCount = 0;

  @override
  void initState() {
    super.initState();
    _calculateSizes();
  }

  void _calculateSizes() {
    int cacheSize = 0;
    int dlCount = 0;

    // Cache calculation
    final cacheDir = Directory('$globalDocumentPath/cache');
    if (cacheDir.existsSync()) {
      for (var file in cacheDir.listSync().whereType<File>()) {
        cacheSize += file.lengthSync();
      }
    }

    // Downloads calculation (only counting .flac and .mp3 in root docDir)
    final docDir = Directory(globalDocumentPath);
    if (docDir.existsSync()) {
      for (var file in docDir.listSync().whereType<File>()) {
        if (file.path.endsWith('.flac') || file.path.endsWith('.mp3')) {
          dlCount++;
        }
      }
    }

    if (mounted) {
      setState(() {
        _cacheSizeBytes = cacheSize;
        _downloadedCount = dlCount;
      });
    }
  }

  void _calculateCacheSize() {
    _calculateSizes();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFFF5252)
            : const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _showAuthDialog(bool isLogin) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Fermer",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: const Alignment(0.0, -0.4),
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isLogin ? "Connexion" : "Créer un compte",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: "Email",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordController,
                        style: const TextStyle(color: Colors.white),
                        obscureText: true,
                        decoration: InputDecoration(
                          hintText: "Mot de passe",
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text(
                                "Annuler",
                                style: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                          Expanded(
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              color: widget.dynamicGradientColors[0],
                              onPressed: () async {
                                final email = emailController.text.trim();
                                final password = passwordController.text.trim();
                                if (email.isEmpty || password.isEmpty) return;

                                try {
                                  if (isLogin) {
                                    await FirebaseAuth.instance
                                        .signInWithEmailAndPassword(
                                          email: email,
                                          password: password,
                                        );
                                    await performCloudRestore();
                                    if (!mounted) return;
                                    _showSnackBar(
                                      "Connexion et restauration réussies !",
                                    );
                                  } else {
                                    await FirebaseAuth.instance
                                        .createUserWithEmailAndPassword(
                                          email: email,
                                          password: password,
                                        );
                                    performCloudBackup();
                                    if (!mounted) return;
                                    _showSnackBar("Compte créé avec succès !");
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.pop(dialogContext);
                                  }
                                } on FirebaseAuthException catch (e) {
                                  if (!mounted) return;
                                  _showSnackBar(
                                    e.message ?? "Erreur d'authentification",
                                    isError: true,
                                  );
                                }
                              },
                              child: Text(
                                isLogin ? "Se connecter" : "S'inscrire",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // --- LE BOUTON GOOGLE PARFAIT ET DÉFINITIF ---
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: CupertinoButton(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          onPressed: () async {
                            try {
                              final googleSignIn = GoogleSignIn.instance;
                              await googleSignIn.initialize(
                                serverClientId:
                                    '154016653293-0f6vgsqeacs4kneqr0bsfplropbb2gvs.apps.googleusercontent.com',
                              );

                              final googleAccount = await googleSignIn
                                  .authenticate();
                              final authClient = googleAccount.authentication;

                              final credential = GoogleAuthProvider.credential(
                                idToken: authClient.idToken,
                              );

                              await FirebaseAuth.instance.signInWithCredential(
                                credential,
                              );
                              await performCloudRestore();

                              if (!mounted) return;
                              _showSnackBar("Connexion Google réussie !");

                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              if (!mounted) return;

                              // Si l'utilisateur annule, on ignore silencieusement
                              if (e is GoogleSignInException &&
                                  e.code ==
                                      GoogleSignInExceptionCode.canceled) {
                                return;
                              }

                              _showSnackBar(
                                "Erreur Google : $e",
                                isError: true,
                              );
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Le VRAI logo officiel de Google (géométrie et couleurs parfaites)
                              Image.network(
                                'https://yt3.googleusercontent.com/bAseQlKvNmjdLQrvYWm_q3QDp8C8YKyYI-nYJewgOkPi0JU1_3X9oFgjrEdzkOlXzLGFxFbnsw=s900-c-k-c0x00ffffff-no-rj',
                                height: 28,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                "Continuer avec Google",
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 20),
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) {
                  return LinearGradient(
                    colors: widget.dynamicGradientColors,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(bounds);
                },
                child: const Text(
                  "Mon Compte",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

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
                                color: widget.dynamicGradientColors[0]
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
                              colors: widget.dynamicGradientColors,
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
                      textAlign:
                          TextAlign.center, // ALIGNEMENT PARFAITEMENT CENTRÉ
                      style: TextStyle(
                        color: isLoggedIn
                            ? widget.dynamicGradientColors[0]
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
                                    onPressed: () => _showAuthDialog(false),
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
                                    color: widget.dynamicGradientColors[0],
                                    onPressed: () => _showAuthDialog(true),
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

          const SizedBox(height: 30),

          // --- LE RESTE DES PARAMÈTRES (INTACT) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: const Text(
                "Paramètres",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.only(left: 16, right: 16, top: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.waveform,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: const Text(
                              "Qualité sonore",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          isLosslessNotifier,
                          isHiResNotifier,
                        ]),
                        builder: (context, _) {
                          int currentQuality = 0;
                          if (isHiResNotifier.value) {
                            currentQuality = 2;
                          } else if (isLosslessNotifier.value) {
                            currentQuality = 1;
                          }

                          return Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: CupertinoSlidingSegmentedControl<int>(
                              backgroundColor: Colors.transparent,
                              thumbColor: Colors.white.withValues(alpha: 0.2),
                              groupValue: currentQuality,
                              onValueChanged: (int? value) {
                                if (value == 0) {
                                  isHiResNotifier.value = false;
                                  isLosslessNotifier.value = false;
                                } else if (value == 1) {
                                  isHiResNotifier.value = false;
                                  isLosslessNotifier.value = true;
                                } else if (value == 2) {
                                  isHiResNotifier.value = true;
                                  isLosslessNotifier.value =
                                      true; // Flac is needed for Hi-Res
                                }
                              },
                              children: {
                                0: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "MP3",
                                    style: TextStyle(
                                      color: currentQuality == 0
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                1: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Lossless",
                                    style: TextStyle(
                                      color: currentQuality == 1
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                2: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Hi-Res",
                                    style: TextStyle(
                                      color: currentQuality == 2
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              },
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.cloud_download,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: const Text(
                              "Préférence de téléchargement",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          isDownloadLosslessNotifier,
                          isDownloadHiResNotifier,
                        ]),
                        builder: (context, _) {
                          int currentQuality = 0;
                          if (isDownloadHiResNotifier.value) {
                            currentQuality = 2;
                          } else if (isDownloadLosslessNotifier.value) {
                            currentQuality = 1;
                          }

                          return Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: CupertinoSlidingSegmentedControl<int>(
                              backgroundColor: Colors.transparent,
                              thumbColor: Colors.white.withValues(alpha: 0.2),
                              groupValue: currentQuality,
                              onValueChanged: (int? value) {
                                if (value == 0) {
                                  isDownloadHiResNotifier.value = false;
                                  isDownloadLosslessNotifier.value = false;
                                } else if (value == 1) {
                                  isDownloadHiResNotifier.value = false;
                                  isDownloadLosslessNotifier.value = true;
                                } else if (value == 2) {
                                  isDownloadHiResNotifier.value = true;
                                  isDownloadLosslessNotifier.value = true;
                                }
                              },
                              children: {
                                0: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "MP3",
                                    style: TextStyle(
                                      color: currentQuality == 0
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                1: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Lossless",
                                    style: TextStyle(
                                      color: currentQuality == 1
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                2: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    "Hi-Res",
                                    style: TextStyle(
                                      color: currentQuality == 2
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              },
                            ),
                          );
                        },
                      ),
                      if (_downloadedCount > 0) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              final docDir = Directory(globalDocumentPath);
                              if (docDir.existsSync()) {
                                final files = docDir.listSync().whereType<File>();
                                for (var file in files) {
                                  if (file.path.endsWith('.flac') || file.path.endsWith('.mp3')) {
                                    // Not in cache, meaning it's a manual download
                                    if (!file.path.replaceAll('\\', '/').contains('/cache/')) {
                                      try {
                                        file.deleteSync();
                                      } catch (e) {
                                        debugPrint("Erreur suppression téléchargement : $e");
                                      }
                                    }
                                  }
                                }
                              }
                              _calculateSizes();
                            },
                            child: Text(
                              "Supprimer $_downloadedCount téléchargement${_downloadedCount > 1 ? 's' : ''}",
                              style: const TextStyle(
                                color: Color(0xFFFF5252),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.drop,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    Text(
                                      "Liquid Glass",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(Icons.lock_outline, size: 16, color: Colors.white54),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isLiquidGlassEnabledNotifier,
                            builder: (context, isLiquidGlassEnabled, _) {
                              return CupertinoSwitch(
                                value: false, // Forcé à false
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: null, // Verrouillé
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.battery_charging,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              "Économiseur de batterie",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isBatterySaverEnabledNotifier,
                            builder: (context, isBatterySaver, _) {
                              return CupertinoSwitch(
                                value: isBatterySaver,
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: (val) {
                                  isBatterySaverEnabledNotifier.value = val;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.archivebox,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Mise en cache",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Conserver temporairement les musiques lues",
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isCacheEnabledNotifier,
                            builder: (context, isCacheEnabled, _) {
                              return CupertinoSwitch(
                                value: isCacheEnabled,
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: (val) {
                                  isCacheEnabledNotifier.value = val;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: isCacheEnabledNotifier,
                        builder: (context, isCacheEnabled, _) {
                          if (!isCacheEnabled) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Column(
                              children: [
                                ValueListenableBuilder<int>(
                                  valueListenable: cacheLimitNotifier,
                                  builder: (context, cacheLimit, _) {
                                    return Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.4,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                        ),
                                      ),
                                      child:
                                          CupertinoSlidingSegmentedControl<int>(
                                            backgroundColor: Colors.transparent,
                                            thumbColor: Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                            groupValue: (cacheLimit == 50 || ![100, 500, 1024, 5120].contains(cacheLimit))
                                                ? 100
                                                : cacheLimit,
                                            onValueChanged: (int? value) {
                                              if (value != null) {
                                                cacheLimitNotifier.value =
                                                    value;
                                                Future.delayed(
                                                  const Duration(milliseconds: 100),
                                                  _calculateSizes,
                                                );
                                              }
                                            },
                                            children: {
                                              100: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "100 Mo",
                                                  style: TextStyle(
                                                    color: cacheLimit == 100
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              500: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "500 Mo",
                                                  style: TextStyle(
                                                    color: cacheLimit == 500
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              1024: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "1 Go",
                                                  style: TextStyle(
                                                    color: cacheLimit == 1024
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              5120: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 12,
                                                    ),
                                                child: Text(
                                                  "5 Go",
                                                  style: TextStyle(
                                                    color: cacheLimit == 5120
                                                        ? Colors.white
                                                        : Colors.white54,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            },
                                          ),
                                    );
                                  },
                                ),
                                if (_cacheSizeBytes > 0) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                    child: CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      onPressed: () {
                                        final cacheDir = Directory(
                                          '$globalDocumentPath/cache',
                                        );
                                        if (cacheDir.existsSync()) {
                                          final files = cacheDir
                                              .listSync()
                                              .whereType<File>();
                                          for (var file in files) {
                                            try {
                                              file.deleteSync();
                                            } catch (e) {
                                              debugPrint(
                                                "Erreur suppression fichier cache : $e",
                                              );
                                            }
                                          }
                                        }
                                        // Vider aussi les pochettes dans le dossier parent (seulement si la musique n'est pas téléchargée)
                                        final docDir = Directory(
                                          globalDocumentPath,
                                        );
                                        if (docDir.existsSync()) {
                                          final files = docDir
                                              .listSync()
                                              .whereType<File>();
                                          for (var file in files) {
                                            if (file.path.endsWith('.jpg') ||
                                                file.path.endsWith('.lrc')) {
                                              try {
                                                final baseName = file.path.split(Platform.pathSeparator).last.replaceAll(RegExp(r'\.(jpg|lrc)$'), '');
                                                final hasMp3 = File('${docDir.path}${Platform.pathSeparator}$baseName.mp3').existsSync();
                                                final hasFlac = File('${docDir.path}${Platform.pathSeparator}$baseName.flac').existsSync();
                                                final hasHiRes = File('${docDir.path}${Platform.pathSeparator}$baseName-hires.flac').existsSync();
                                                
                                                if (!hasMp3 && !hasFlac && !hasHiRes) {
                                                  file.deleteSync();
                                                }
                                              } catch (e) {
                                                debugPrint(
                                                  "Erreur suppression image : $e",
                                                );
                                              }
                                            }
                                          }
                                        }

                                        _calculateCacheSize();
                                      },
                                      child: Text(
                                        "Vider le cache (${(_cacheSizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo)",
                                        style: const TextStyle(
                                          color: Color(0xFFFF5252),
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 30),

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              CupertinoIcons.waveform_path,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  "Fondu enchaîné",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: isCrossfadeEnabledNotifier,
                            builder: (context, isCrossfadeEnabled, _) {
                              return CupertinoSwitch(
                                value: isCrossfadeEnabled,
                                activeTrackColor:
                                    widget.dynamicGradientColors[0],
                                onChanged: (val) {
                                  isCrossfadeEnabledNotifier.value = val;
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: isCrossfadeEnabledNotifier,
                        builder: (context, isCrossfadeEnabled, _) {
                          if (!isCrossfadeEnabled) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: ValueListenableBuilder<int>(
                              valueListenable: crossfadeDurationNotifier,
                              builder: (context, crossfadeSecs, _) {
                                final badgeColors =
                                    widget.dynamicGradientColors.length >= 2
                                        ? widget.dynamicGradientColors
                                            .take(2)
                                            .toList()
                                        : [
                                            widget.dynamicGradientColors[0],
                                            widget.dynamicGradientColors[0],
                                          ];
                                final avgLuminance =
                                    badgeColors
                                        .map((c) => c.computeLuminance())
                                        .reduce((a, b) => a + b) /
                                    badgeColors.length;
                                final badgeTextColor =
                                    avgLuminance > 0.55
                                        ? const Color(0xFF1E1E1E)
                                        : Colors.white;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            "Durée de la transition",
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: badgeColors,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              "$crossfadeSecs s",
                                              style: TextStyle(
                                                color: badgeTextColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 6,
                                          activeTrackColor: Colors.transparent,
                                          inactiveTrackColor:
                                              Colors.white.withValues(
                                                alpha: 0.1,
                                              ),
                                          thumbColor: Colors.white,
                                          overlayColor: widget
                                              .dynamicGradientColors[0]
                                              .withValues(alpha: 0.2),
                                          trackShape: _GradientSliderTrackShape(
                                            gradient: LinearGradient(
                                              colors:
                                                  widget.dynamicGradientColors,
                                            ),
                                          ),
                                        ),
                                        child: Slider(
                                          value: crossfadeSecs.toDouble(),
                                          min: 1.0,
                                          max: 12.0,
                                          divisions: 11,
                                          onChanged: (val) {
                                            crossfadeDurationNotifier.value =
                                                val.round();
                                          },
                                        ),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: const [
                                          Text(
                                            "1 s",
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            "12 s",
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 220),
        ],
      ),
    );
  }
}

class _GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  final LinearGradient gradient;

  const _GradientSliderTrackShape({required this.gradient});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );

    final inactiveRect = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
    );

    final Paint activePaint = Paint()
      ..shader = gradient.createShader(trackRect);

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.white12;

    final trackRadius = Radius.circular(trackRect.height / 2);

    if (activeRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          activeRect,
          topLeft: trackRadius,
          bottomLeft: trackRadius,
          topRight: inactiveRect.width <= 0 ? trackRadius : Radius.zero,
          bottomRight: inactiveRect.width <= 0 ? trackRadius : Radius.zero,
        ),
        activePaint,
      );
    }

    if (inactiveRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromRectAndCorners(
          inactiveRect,
          topRight: trackRadius,
          bottomRight: trackRadius,
          topLeft: activeRect.width <= 0 ? trackRadius : Radius.zero,
          bottomLeft: activeRect.width <= 0 ? trackRadius : Radius.zero,
        ),
        inactivePaint,
      );
    }
  }
}
