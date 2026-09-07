import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mmkv/mmkv.dart';
import 'package:musicality/core/globals.dart';

void showEditPlaylistDialog({
  required BuildContext context,
  required String oldName,
  required List<Color> themeColors,
}) {
  final TextEditingController renameController = TextEditingController(
    text: oldName,
  );
  final ValueNotifier<String?> selectedImageNotifier = ValueNotifier(
    playlistImagesNotifier.value[oldName],
  );

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: "Fermer",
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Align(
        alignment: const Alignment(0.0, -0.4),
        child: Material(
          type: MaterialType.transparency,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: FadeTransition(
              opacity: animation,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              colors: themeColors,
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ).createShader(
                              Rect.fromLTWH(
                                0,
                                0,
                                bounds.width,
                                bounds.height,
                              ),
                            );
                          },
                          child: const Text(
                            "Modifier la Playlist",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        ValueListenableBuilder<String?>(
                          valueListenable: selectedImageNotifier,
                          builder: (context, imagePath, _) {
                            final hasValidImage =
                                imagePath != null &&
                                imagePath.isNotEmpty &&
                                File(imagePath).existsSync();

                            return Stack(
                              clipBehavior: Clip.none,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final xfile = await picker.pickImage(
                                      source: ImageSource.gallery,
                                    );
                                    if (xfile != null) {
                                      selectedImageNotifier.value = xfile.path;
                                    }
                                  },
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: hasValidImage
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Image.file(
                                              File(imagePath),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : const Icon(
                                            CupertinoIcons.camera_fill,
                                            color: Colors.white54,
                                            size: 32,
                                          ),
                                  ),
                                ),
                                if (hasValidImage)
                                  Positioned(
                                    top: -10,
                                    right: -10,
                                    child: GestureDetector(
                                      onTap: () {
                                        selectedImageNotifier.value = null;
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: themeColors,
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black54,
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          CupertinoIcons.minus,
                                          color: Colors.white,
                                          size: 16,
                                          weight: 800,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 20),

                        Theme(
                          data: Theme.of(context).copyWith(
                            textSelectionTheme: TextSelectionThemeData(
                              selectionHandleColor: themeColors[0],
                              selectionColor: themeColors[0].withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: TextField(
                            controller: renameController,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            cursorColor: Colors.white,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              hintText: "Nom de la playlist...",
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 20,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
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
                                    final currentContents =
                                        Map<String, Set<String>>.from(
                                          playlistContentsNotifier.value,
                                        );
                                    final currentImages =
                                        Map<String, String>.from(
                                          playlistImagesNotifier.value,
                                        );
                                    final currentList = List<String>.from(
                                      customPlaylistsNotifier.value,
                                    );

                                    currentContents.remove(oldName);
                                    currentList.remove(oldName);
                                    currentImages.remove(oldName);

                                    final mmkv = MMKV.defaultMMKV();
                                    mmkv.removeValue(
                                      'playlist_content_$oldName',
                                    );
                                    mmkv.removeValue(
                                      'playlist_image_$oldName',
                                    );

                                    playlistContentsNotifier.value =
                                        currentContents;
                                    customPlaylistsNotifier.value = currentList;
                                    playlistImagesNotifier.value =
                                        currentImages;

                                    Navigator.pop(context);
                                  },
                                  child: const Text(
                                    "Supprimer",
                                    style: TextStyle(
                                      color: Color(0xFFFF5252),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: themeColors,
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  onPressed: () {
                                    final newName = renameController.text
                                        .trim();
                                    final newImage =
                                        selectedImageNotifier.value ?? '';

                                    if (newName.isNotEmpty) {
                                      final currentContents =
                                          Map<String, Set<String>>.from(
                                            playlistContentsNotifier.value,
                                          );
                                      final currentImages =
                                          Map<String, String>.from(
                                            playlistImagesNotifier.value,
                                          );
                                      final currentList = List<String>.from(
                                        customPlaylistsNotifier.value,
                                      );

                                      if (newName != oldName) {
                                        final playlistSongs =
                                            currentContents[oldName] ??
                                            <String>{};
                                        currentContents.remove(oldName);
                                        currentContents[newName] =
                                            playlistSongs;

                                        final index = currentList.indexOf(
                                          oldName,
                                        );
                                        if (index != -1) {
                                          currentList[index] = newName;
                                        } else {
                                          currentList.add(newName);
                                        }

                                        if (currentImages.containsKey(
                                          oldName,
                                        )) {
                                          final img = currentImages[oldName];
                                          currentImages.remove(oldName);
                                          if (img != null) {
                                            currentImages[newName] = img;
                                          }
                                        }

                                        final mmkv = MMKV.defaultMMKV();
                                        mmkv.removeValue(
                                          'playlist_content_$oldName',
                                        );
                                        mmkv.removeValue(
                                          'playlist_image_$oldName',
                                        );
                                      }

                                      if (newImage.isNotEmpty) {
                                        currentImages[newName] = newImage;
                                      } else {
                                        currentImages.remove(newName);
                                      }

                                      playlistContentsNotifier.value =
                                          currentContents;
                                      customPlaylistsNotifier.value =
                                          currentList;
                                      playlistImagesNotifier.value =
                                          currentImages;
                                    }
                                    Navigator.pop(context);
                                  },
                                  child: const Text(
                                    "Valider",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  ).then((_) {
    renameController.dispose();
    selectedImageNotifier.dispose();
  });
}
