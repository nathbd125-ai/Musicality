import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:musicality/core/globals.dart';

Future<void> showAuthDialog({
  required BuildContext context,
  required bool isLogin,
  required Color primaryColor,
  required void Function(String message, {bool isError}) showSnackBar,
}) async {
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
                    const SizedBox(height: 20),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Email",
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        prefixIcon: Icon(
                          CupertinoIcons.mail,
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
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Mot de passe",
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                        prefixIcon: Icon(
                          CupertinoIcons.lock,
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
                            color: primaryColor,
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
                                  showSnackBar(
                                    "Connexion et restauration réussies !",
                                  );
                                } else {
                                  await FirebaseAuth.instance
                                      .createUserWithEmailAndPassword(
                                        email: email,
                                        password: password,
                                      );
                                  performCloudBackup();
                                  showSnackBar("Compte créé avec succès !");
                                }
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              } on FirebaseAuthException catch (e) {
                                showSnackBar(
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
                              clientId: Platform.isIOS
                                  ? '154016653293-pflk08mmpvoglsm04ennrvj9u4itut49.apps.googleusercontent.com'
                                  : null,
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

                            showSnackBar("Connexion Google réussie !");

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            // Si l'utilisateur annule, on ignore silencieusement
                            if (e is GoogleSignInException &&
                                e.code ==
                                    GoogleSignInExceptionCode.canceled) {
                              return;
                            }

                            showSnackBar(
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

                    // --- BOUTON APPLE (disponible sur toutes les plateformes) ---
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        onPressed: () async {
                          try {
                            final appleProvider = AppleAuthProvider();
                            appleProvider.addScope('email');
                            appleProvider.addScope('name');

                            await FirebaseAuth.instance.signInWithProvider(
                              appleProvider,
                            );
                            await performCloudRestore();

                            showSnackBar("Connexion Apple réussie !");

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (e) {
                            final isNotAllowed = e is FirebaseAuthException &&
                                e.code == 'operation-not-allowed';
                            showSnackBar(
                              isNotAllowed
                                  ? "La connexion Apple n'est pas encore disponible sur Android. Utilise Google ou un compte email."
                                  : "Erreur Apple : $e",
                              isError: true,
                            );
                          }
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.apple,
                              color: Colors.black,
                              size: 26,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Continuer avec Apple",
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
