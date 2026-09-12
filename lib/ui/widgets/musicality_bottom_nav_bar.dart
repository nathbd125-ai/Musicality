import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:musicality/core/globals.dart';

class MusicalityBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  static final Stream<User?> _authStateStream =
      FirebaseAuth.instance.authStateChanges();
  static bool? _cachedGoogleAvatarExists;
  static String? _lastVerifiedLocalPath;
  static bool _lastVerifiedLocalExists = false;

  const MusicalityBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static bool _checkLocalImage(String? path) {
    if (path == null || path.isEmpty) return false;
    if (path == _lastVerifiedLocalPath) return _lastVerifiedLocalExists;
    _lastVerifiedLocalPath = path;
    _lastVerifiedLocalExists = File(path).existsSync();
    return _lastVerifiedLocalExists;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return Align(
      alignment: Alignment.center,
      child: MediaQuery(
        data: mediaQuery.copyWith(
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
        ),
        child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: StreamBuilder<User?>(
              stream: _authStateStream,
              builder: (context, authSnapshot) {
                final user = authSnapshot.data;

                return ValueListenableBuilder<String?>(
                  valueListenable: userProfileImageNotifier,
                  builder: (context, localImagePath, _) {
                    // Logique de l'icône (Locale > Google > Défaut)
                    final hasLocalImage = _checkLocalImage(localImagePath);
                    final hasGoogleImage =
                        user != null && user.photoURL != null;

                    final cachedGoogleAvatar = File(
                      '$globalDocumentPath/cached_google_avatar.jpg',
                    );
                    final hasCachedGoogle = _cachedGoogleAvatarExists ??=
                        cachedGoogleAvatar.existsSync();

                    Widget accountIcon;
                    if (hasLocalImage) {
                      accountIcon = ClipOval(
                        child: Image.file(
                          File(localImagePath!),
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                      );
                    } else if (hasCachedGoogle) {
                      accountIcon = ClipOval(
                        child: Image.file(
                          cachedGoogleAvatar,
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                        ),
                      );
                    } else if (hasGoogleImage) {
                      accountIcon = ClipOval(
                        child: Image.network(
                          user.photoURL!,
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                          errorBuilder:
                              (context, error, stackTrace) => const Icon(
                                CupertinoIcons.person_fill,
                                size: 24,
                              ),
                        ),
                      );
                    } else {
                      accountIcon = const Icon(
                        CupertinoIcons.person_alt_circle,
                      );
                    }

                    return SizedBox(
                      height: 56,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width,
                          height: 56,
                          child: BottomNavigationBar(
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            selectedItemColor: Colors.white,
                            unselectedItemColor: Colors.white54,
                            selectedFontSize: 11,
                            unselectedFontSize: 11,
                            type: BottomNavigationBarType.fixed,
                            currentIndex: currentIndex,
                            onTap: (index) {
                              if (index != currentIndex &&
                                  isHapticFeedbackEnabledNotifier.value) {
                                HapticFeedback.selectionClick();
                              }
                              onTap(index);
                            },
                            items: [
                              const BottomNavigationBarItem(
                                icon: Icon(Icons.home),
                                label: 'Accueil',
                              ),
                              const BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.person_2_fill),
                                label: 'Artistes',
                              ),
                              const BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.music_note),
                                label: 'Musiques',
                              ),
                              const BottomNavigationBarItem(
                                icon: Icon(CupertinoIcons.heart_fill),
                                label: 'Bibliothèque',
                              ),
                              // 👇 L'ICÔNE DYNAMIQUE EST ICI 👇
                              BottomNavigationBarItem(
                                icon: accountIcon,
                                label: 'Compte',
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
  }
}
