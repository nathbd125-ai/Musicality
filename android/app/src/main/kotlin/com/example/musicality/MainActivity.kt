package com.musicality // /!\ ATTENTION : Laisse TA ligne package actuelle ici !

import android.content.Intent
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.util.DisplayMetrics
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity: AudioServiceActivity() {

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