package com.kerolosadel.mnis_app

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (fingerprint/Face unlock) shows its prompt via Android's
// BiometricPrompt, which only works inside a FragmentActivity. The default
// Flutter template uses plain FlutterActivity, which has no fragment host —
// on that base class, every authenticate() call fails (usually silently, or
// with a "no_fragment_activity" platform exception), no matter how correct
// the Dart-side code is. This was the real reason biometric never worked.
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val SMS_CHANNEL = "mnis/sms_autofill"
        private val OTP_REGEX = Regex("(?<!\\d)(\\d{6})(?!\\d)")
    }

    private var smsChannel: MethodChannel? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        smsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startInAppSmsListener" -> {
                        val started = startInAppSmsListener()
                        result.success(started)
                    }
                    "stopInAppSmsListener" -> {
                        stopInAppSmsListener()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    // Purely in-process Telephony broadcast listener using the app's already-scoped
    // RECEIVE_SMS permission — never launches Google Play Services consent Activities
    // or pauses MainActivity. Falls back smoothly to keyboard AutofillHints.oneTimeCode
    // when permission is declined.
    private fun startInAppSmsListener(): Boolean {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECEIVE_SMS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            return false
        }

        stopInAppSmsListener()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (Telephony.Sms.Intents.SMS_RECEIVED_ACTION != intent.action) return
                try {
                    val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                    if (messages.isEmpty()) return
                    val fullBody = buildString {
                        for (msg in messages) {
                            append(msg.messageBody ?: "")
                            append('\n')
                        }
                    }
                    val otp = OTP_REGEX.find(fullBody)?.groupValues?.get(1)
                    if (!otp.isNullOrEmpty()) {
                        stopInAppSmsListener()
                        runOnUiThread {
                            smsChannel?.invokeMethod("onSmsOtpReceived", otp)
                        }
                    }
                } catch (_: Throwable) {
                    // Never crash on malformed carrier PDUs.
                }
            }
        }

        val intentFilter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, intentFilter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(receiver, intentFilter)
            }
            smsReceiver = receiver
            return true
        } catch (_: Throwable) {
            smsReceiver = null
            return false
        }
    }

    private fun stopInAppSmsListener() {
        val receiver = smsReceiver ?: return
        smsReceiver = null
        try {
            unregisterReceiver(receiver)
        } catch (_: Throwable) {
            // Receiver already unregistered.
        }
    }

    override fun onDestroy() {
        stopInAppSmsListener()
        smsChannel?.setMethodCallHandler(null)
        smsChannel = null
        super.onDestroy()
    }
}
