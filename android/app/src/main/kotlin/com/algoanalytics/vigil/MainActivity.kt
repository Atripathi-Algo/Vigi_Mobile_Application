package com.algoanalytics.vigil

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: the Health Connect permission dialog needs it.
class MainActivity : FlutterFragmentActivity() {
    private var googleAuth: GoogleAuthBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = GoogleAuthBridge(this)
        googleAuth = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GoogleAuthBridge.CHANNEL).setMethodCallHandler(bridge)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (googleAuth?.handleActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
