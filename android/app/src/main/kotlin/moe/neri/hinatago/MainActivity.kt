package moe.neri.hinatago

import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import im.nfc.flutter_nfc_kit.FlutterNfcKitPlugin
import android.os.Bundle
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {
    private var pendingTag: Tag? = null
    private val nfcChannel = "moe.neri.hinatago/nfc_launcher"
    private val appUpdateChannel = "moe.neri.hinatago/app_update"
    private val displayRotationChannel = "moe.neri.hinatago/display_rotation"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nfcChannel).setMethodCallHandler { call, result ->
            if (call.method == "getInitialTag") {
                pendingTag?.let {
                    Log.d("MainActivity", "Relaying buffered tag to FlutterNfcKit")
                    FlutterNfcKitPlugin.handleTag(it)
                    pendingTag = null // Clear after relay
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appUpdateChannel).setMethodCallHandler { call, result ->
            if (call.method == "isSplitApk") {
                result.success(isSplitApkInstall())
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, displayRotationChannel).setMethodCallHandler { call, result ->
            if (call.method == "getDisplayRotation") {
                result.success(getDisplayRotation())
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        intent?.let(::handleNfcIntent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNfcIntent(intent)
    }

    private fun handleNfcIntent(intent: Intent) {
        if (NfcAdapter.ACTION_NDEF_DISCOVERED == intent.action ||
            NfcAdapter.ACTION_TECH_DISCOVERED == intent.action ||
            NfcAdapter.ACTION_TAG_DISCOVERED == intent.action
        ) {
            val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
            tag?.let {
                Log.d("MainActivity", "NFC Intent detected, buffering tag")
                pendingTag = it
                // Also try to relay immediately in case Flutter is already running
                FlutterNfcKitPlugin.handleTag(it)
            }
        }
    }

    private fun isSplitApkInstall(): Boolean {
        return try {
            @Suppress("DEPRECATION")
            val applicationInfo = packageManager.getApplicationInfo(packageName, 0)
            !applicationInfo.splitSourceDirs.isNullOrEmpty()
        } catch (_: Exception) {
            false
        }
    }

    private fun getDisplayRotation(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }
    }
}
