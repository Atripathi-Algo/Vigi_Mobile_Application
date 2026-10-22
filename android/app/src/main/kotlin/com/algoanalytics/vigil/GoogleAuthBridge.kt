package com.algoanalytics.vigil

import android.accounts.Account
import android.accounts.AccountManager
import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import androidx.fragment.app.FragmentActivity
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.RevokeAccessRequest
import com.google.android.gms.common.AccountPicker
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.Scope
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Google sign-in for calendar access, using Google's own Android Authorization API.
 * No client id, secret or redirect is stored in the app: Google matches the app by package name
 * and signing key. Each call names the account, so two accounts work side by side, and a token
 * is fetched silently once the user has approved the scope.
 */
class GoogleAuthBridge(private val activity: FragmentActivity) : MethodChannel.MethodCallHandler {
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "available" -> result.success(
                GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) == ConnectionResult.SUCCESS
            )
            "sha1" -> result.success(signingSha1())
            "pickAccount" -> pickAccount(result)
            "authorize" -> authorize(
                call.argument<String>("email"),
                call.argument<List<String>>("scopes"),
                call.argument<Boolean>("interactive") == true,
                result
            )
            "revoke" -> revoke(call.argument<String>("email"), call.argument<List<String>>("scopes"), result)
            else -> result.notImplemented()
        }
    }

    private fun pickAccount(result: MethodChannel.Result) {
        if (pending != null) return result.error("BUSY", "Another Google request is open.", null)
        try {
            val options = AccountPicker.AccountChooserOptions.Builder()
                .setAllowableAccountsTypes(listOf("com.google"))
                .build()
            pending = result
            activity.startActivityForResult(AccountPicker.newChooseAccountIntent(options), REQ_PICK)
        } catch (e: Exception) {
            pending = null
            result.error("PICKER", e.message ?: e.toString(), null)
        }
    }

    private fun authorize(email: String?, scopes: List<String>?, interactive: Boolean, result: MethodChannel.Result) {
        if (email.isNullOrBlank() || scopes.isNullOrEmpty()) {
            return result.error("ARGS", "An account and at least one scope are needed.", null)
        }
        val request = AuthorizationRequest.builder()
            .setRequestedScopes(scopes.map { Scope(it) })
            .setAccount(Account(email, "com.google"))
            .build()
        Identity.getAuthorizationClient(activity).authorize(request)
            .addOnSuccessListener { r ->
                if (r.hasResolution()) {
                    // Needs the user's approval. Background syncs must never open a screen.
                    val intent = r.pendingIntent
                    if (!interactive || intent == null) {
                        result.success(mapOf("status" to "consent_needed"))
                    } else if (pending != null) {
                        result.error("BUSY", "Another Google request is open.", null)
                    } else {
                        try {
                            pending = result
                            activity.startIntentSenderForResult(intent.intentSender, REQ_CONSENT, null, 0, 0, 0, null)
                        } catch (e: IntentSender.SendIntentException) {
                            pending = null
                            result.success(mapOf("status" to "error", "message" to (e.message ?: e.toString())))
                        }
                    }
                } else {
                    val token = r.accessToken
                    if (token == null) {
                        result.success(mapOf("status" to "error", "message" to "Google returned no token."))
                    } else {
                        result.success(mapOf("status" to "ok", "token" to token))
                    }
                }
            }
            .addOnFailureListener { e ->
                result.success(mapOf("status" to "error", "message" to (e.message ?: e.toString())))
            }
    }

    private fun revoke(email: String?, scopes: List<String>?, result: MethodChannel.Result) {
        if (email.isNullOrBlank() || scopes.isNullOrEmpty()) return result.success(false)
        val request = RevokeAccessRequest.builder()
            .setAccount(Account(email, "com.google"))
            .setScopes(scopes.map { Scope(it) })
            .build()
        Identity.getAuthorizationClient(activity).revokeAccess(request)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { result.success(false) }
    }

    /** Called from MainActivity. Returns true when the request code was ours. */
    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK && requestCode != REQ_CONSENT) return false
        val result = pending ?: return true
        pending = null
        if (requestCode == REQ_PICK) {
            val email = if (resultCode == Activity.RESULT_OK) data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME) else null
            result.success(email)
            return true
        }
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(mapOf("status" to "cancelled"))
            return true
        }
        try {
            val r = Identity.getAuthorizationClient(activity).getAuthorizationResultFromIntent(data)
            val token = r.accessToken
            if (token == null) {
                result.success(mapOf("status" to "error", "message" to "Google returned no token."))
            } else {
                result.success(mapOf("status" to "ok", "token" to token))
            }
        } catch (e: Exception) {
            result.success(mapOf("status" to "error", "message" to (e.message ?: e.toString())))
        }
        return true
    }

    /** SHA-1 of the key this APK is signed with: what the Google Cloud OAuth client must list. */
    @Suppress("DEPRECATION")
    private fun signingSha1(): String? = try {
        val pm = activity.packageManager
        val signer = if (Build.VERSION.SDK_INT >= 28) {
            pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners?.firstOrNull()
        } else {
            pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNATURES).signatures?.firstOrNull()
        }
        signer?.let { s ->
            MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString(":") { "%02X".format(it) }
        }
    } catch (e: Exception) {
        null
    }

    companion object {
        const val CHANNEL = "vigil/google_auth"
        private const val REQ_PICK = 7101
        private const val REQ_CONSENT = 7102
    }
}
