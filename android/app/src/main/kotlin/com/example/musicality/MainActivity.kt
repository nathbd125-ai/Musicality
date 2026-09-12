package com.musicality // /!\ ATTENTION : Laisse TA ligne package actuelle ici !

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.util.DisplayMetrics
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: AudioServiceActivity() {

    private val CHANNEL = "com.musicality/cross_app_sync"
    private var methodChannel: MethodChannel? = null

    private val lyricsReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.musicality.ACTION_LYRICS_UPDATED") {
                val songId = intent.getStringExtra("songId") ?: ""
                val baseName = intent.getStringExtra("baseName") ?: ""
                val lrcContent = intent.getStringExtra("lrcContent") ?: ""
                if (baseName.isNotEmpty() && lrcContent.isNotEmpty()) {
                    methodChannel?.invokeMethod("onLyricsReceived", mapOf(
                        "songId" to songId,
                        "baseName" to baseName,
                        "lrcContent" to lrcContent
                    ))
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "broadcastLyricsUpdate" -> {
                    val songId = call.argument<String>("songId") ?: ""
                    val baseName = call.argument<String>("baseName") ?: ""
                    val lrcContent = call.argument<String>("lrcContent") ?: ""

                    // Diffuser à la fois vers com.musicality et com.musicality.studio
                    val targetPackages = listOf("com.musicality", "com.musicality.studio")
                    for (pkg in targetPackages) {
                        try {
                            val broadcastIntent = Intent("com.musicality.ACTION_LYRICS_UPDATED").apply {
                                `package` = pkg
                                putExtra("songId", songId)
                                putExtra("baseName", baseName)
                                putExtra("lrcContent", lrcContent)
                            }
                            sendBroadcast(broadcastIntent)
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        try {
            val filter = IntentFilter("com.musicality.ACTION_LYRICS_UPDATED")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(lyricsReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(lyricsReceiver, filter)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(lyricsReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onMultiWindowModeChanged(isInMultiWindowMode: Boolean, newConfig: Configuration?) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        if (isInMultiWindowMode) {
            preventFreeformFloatingWindow()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (isInPictureInPictureMode) {
            try {
                val intent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun preventFreeformFloatingWindow() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            val displayMetrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(displayMetrics)
            val screenW = displayMetrics.widthPixels
            val screenH = displayMetrics.heightPixels

            if (screenW <= 0 || screenH <= 0) return

            val windowBounds = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                windowManager.currentWindowMetrics.bounds
            } else {
                val r = Rect()
                window.decorView.getWindowVisibleDisplayFrame(r)
                r
            }

            val winW = windowBounds.width()
            val winH = windowBounds.height()

            if (winW <= 0 || winH <= 0) return

            // En écran splité (haut/bas ou gauche/droite), au moins une des dimensions occupe la totalité de l'écran.
            val isSplitScreen = (winW >= screenW * 0.90) || (winH >= screenH * 0.90)

            // En petite fenêtre flottante (freeform/pop-up sous HyperOS ou One UI), les deux dimensions sont réduites.
            if (!isSplitScreen && winW < screenW * 0.85 && winH < screenH * 0.85) {
                val intent = Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                }
                startActivity(intent)
            }
        } catch (_: Exception) {}
    }
}