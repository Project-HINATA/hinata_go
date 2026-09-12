package moe.neri.hinatago

import android.content.Intent
import android.net.Uri
import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.CookieManager
import java.net.CookiePolicy
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/** Native Prism session, Passkey, card and location bridge for Android. */
class PrismNativeBridge(private val activity: Activity) {
    companion object {
        const val CHANNEL = "moe.neri.hinatago/prism_native"
        const val LOCATION_PERMISSION_REQUEST = 49172
        private const val BASE_URL = "https://link.neri.moe"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { command -> mainHandler.post(command) }
    private val ioExecutor: ExecutorService = Executors.newCachedThreadPool()
    private val credentialManager = CredentialManager.create(activity)
    private val cookieManager = CookieManager(null, CookiePolicy.ACCEPT_ALL)
    private val locationManager =
        activity.getSystemService(LocationManager::class.java)

    private var disposed = false
    private var channel: MethodChannel? = null
    private var pendingPermissionLogin: LoginRequest? = null
    private var locationListener: LocationListener? = null
    private var locationTimeout: Runnable? = null

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            handle(call, result)
        }
    }

    fun handlePermissionResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != LOCATION_PERMISSION_REQUEST) return false
        val request = pendingPermissionLogin ?: return true
        pendingPermissionLogin = null
        val granted = grantResults.any { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            fail(request.result, "location_denied", "需要定位权限才能确认你位于店内")
        } else {
            requestLocation(request)
        }
        return true
    }

    fun dispose() {
        disposed = true
        cancelLocationRequest()
        ioExecutor.shutdownNow()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            fail(result, "bridge_unavailable", "PRiSM 服务不可用")
            return
        }
        when (call.method) {
            "authenticateMunet" -> authenticateMunet(result)
            "request" -> apiRequest(call, result)
            "authenticatePasskey" -> authenticatePasskey(result)
            "cards" -> loadCards(result)
            "loginMachine" -> loginMachine(call, result)
            else -> result.notImplemented()
        }
    }

    private fun apiRequest(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: return fail(result, "invalid_arguments", "缺少请求地址")
        val body = call.argument<String>("body")
        val request = LoginRequest("", "", result, path, body)
        if (call.argument<Boolean>("requireLocation") != true) { performMachineLogin(request, null); return }
        if (!hasLocationPermission()) {
            if (pendingPermissionLogin != null) { fail(result, "location_busy", "正在等待定位权限"); return }
            pendingPermissionLogin = request
            activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), LOCATION_PERMISSION_REQUEST)
        } else requestLocation(request)
    }

    private var pendingMunet: MethodChannel.Result? = null
    private fun authenticateMunet(result: MethodChannel.Result) {
        if (pendingMunet != null) { fail(result, "authentication_busy", "登录正在进行"); return }
        pendingMunet = result
        try {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("$BASE_URL/api/v1/appclip/auth/start")))
            mainHandler.postDelayed({
                if (pendingMunet === result) { pendingMunet = null; fail(result, "authentication_cancelled", "") }
            }, 120_000)
        } catch (error: Exception) { pendingMunet = null; fail(result, "authentication_failed", errorMessage(error)) }
    }

    fun handleAuthCallback(intent: Intent): Boolean {
        val uri = intent.data ?: return false
        if (uri.scheme != "hinata-prism-auth") return false
        val result = pendingMunet ?: return true
        pendingMunet = null
        val code = uri.getQueryParameter("code")
        if (code.isNullOrBlank()) { fail(result, "authentication_cancelled", ""); return true }
        ioExecutor.execute {
            try { request("POST", "/api/v1/appclip/auth/exchange", JSONObject().put("code", code).toString()); succeed(result, null) }
            catch (error: Exception) { fail(result, "authentication_failed", errorMessage(error)) }
        }
        return true
    }

    private fun authenticatePasskey(result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val optionsJson = request("GET", "/api/v1/auth/passkey/options")
                val request = GetCredentialRequest(
                    listOf(GetPublicKeyCredentialOption(optionsJson)),
                )
                mainHandler.post {
                    if (disposed) {
                        fail(result, "bridge_unavailable", "PRiSM 服务不可用")
                        return@post
                    }
                    credentialManager.getCredentialAsync(
                        activity,
                        request,
                        null,
                        mainExecutor,
                        object : CredentialManagerCallback<
                            GetCredentialResponse,
                            GetCredentialException
                        > {
                            override fun onResult(response: GetCredentialResponse) {
                                val credential = response.credential
                                if (credential !is PublicKeyCredential) {
                                    fail(result, "passkey_invalid", "返回的 Passkey 类型无效")
                                    return
                                }
                                submitPasskey(credential.authenticationResponseJson, result)
                            }

                            override fun onError(error: GetCredentialException) {
                                if (error is GetCredentialCancellationException) {
                                    fail(result, "authentication_cancelled", "")
                                    return
                                }
                                fail(
                                    result,
                                    "passkey_error",
                                    error.errorMessage?.toString()?.ifBlank {
                                        "Passkey 登录未完成"
                                    } ?: "Passkey 登录未完成",
                                )
                            }
                        },
                    )
                }
            } catch (error: Exception) {
                fail(result, (error as? ApiException)?.code ?: "prism_error", errorMessage(error))
            }
        }
    }

    private fun submitPasskey(assertionJson: String, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                request(
                    "POST",
                    "/api/v1/auth/passkey",
                    assertionJson,
                )
                succeed(result, null)
            } catch (error: Exception) {
                fail(result, "prism_error", errorMessage(error))
            }
        }
    }

    private fun loadCards(result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val body = JSONObject(request("GET", "/api/v1/cards"))
                val cards = body.optJSONArray("cards") ?: JSONArray()
                val output = ArrayList<HashMap<String, Any?>>(cards.length())
                for (index in 0 until cards.length()) {
                    val card = cards.getJSONObject(index)
                    val value = hashMapOf<String, Any?>(
                        "id" to card.getString("id"),
                        "label" to card.getString("label"),
                        "accessCode" to card.getString("accessCode"),
                    )
                    if (!card.isNull("disabledAt")) {
                        value["disabledAt"] = card.getString("disabledAt")
                    }
                    output.add(value)
                }
                succeed(result, output)
            } catch (error: Exception) {
                fail(result, (error as? ApiException)?.code ?: "prism_error", errorMessage(error))
            }
        }
    }

    private fun loginMachine(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<*, *>
        val cardId = arguments?.get("cardId") as? String
        val ticket = arguments?.get("ticket") as? String
        if (cardId.isNullOrBlank() || ticket.isNullOrBlank()) {
            fail(result, "invalid_arguments", "缺少机台登录参数")
            return
        }

        val request = LoginRequest(cardId, ticket, result)
        if (arguments?.get("requireLocation") == false) {
            performMachineLogin(request, null)
            return
        }
        if (!hasLocationPermission()) {
            if (pendingPermissionLogin != null) {
                fail(result, "location_busy", "正在等待定位权限")
                return
            }
            pendingPermissionLogin = request
            activity.requestPermissions(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION,
                ),
                LOCATION_PERMISSION_REQUEST,
            )
            return
        }
        requestLocation(request)
    }

    private fun requestLocation(request: LoginRequest) {
        if (locationListener != null) {
            fail(request.result, "location_busy", "正在获取当前位置，请稍后再试")
            return
        }
        val providers = try {
            locationManager.allProviders
                .filter {
                    it != LocationManager.PASSIVE_PROVIDER &&
                        locationManager.isProviderEnabled(it)
                }
                .sortedBy { provider ->
                    when (provider) {
                        LocationManager.NETWORK_PROVIDER -> 0
                        LocationManager.GPS_PROVIDER -> 1
                        else -> 2
                    }
                }
        } catch (_: SecurityException) {
            fail(request.result, "location_denied", "需要定位权限才能确认你位于店内")
            return
        }
        if (providers.isEmpty()) {
            fail(request.result, "location_unavailable", "无法获取当前位置，请打开系统定位后重试")
            return
        }

        val lastKnown = providers.mapNotNull { provider ->
            try {
                locationManager.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            }
        }.maxByOrNull { it.time }
        if (lastKnown != null && System.currentTimeMillis() - lastKnown.time < 15_000) {
            performMachineLogin(request, lastKnown)
            return
        }

        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                finishLocation(request, location, this)
            }

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) = Unit

            @Suppress("DEPRECATION")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
        }
        locationListener = listener
        locationTimeout = Runnable {
            if (locationListener === listener) {
                cancelLocationRequest()
                fail(request.result, "location_timeout", "无法获取当前位置，请重试")
            }
        }.also { mainHandler.postDelayed(it, 15_000) }
        try {
            locationManager.requestLocationUpdates(
                providers.first(),
                1_000L,
                0f,
                listener,
                Looper.getMainLooper(),
            )
        } catch (error: SecurityException) {
            cancelLocationRequest()
            fail(request.result, "location_denied", "需要定位权限才能确认你位于店内")
        }
    }

    private fun finishLocation(
        request: LoginRequest,
        location: Location,
        listener: LocationListener,
    ) {
        if (locationListener !== listener) return
        cancelLocationRequest()
        performMachineLogin(request, location)
    }

    private fun performMachineLogin(request: LoginRequest, location: Location?) {
        if (request.path == null) mainHandler.post { channel?.invokeMethod("machineLoginSending", null) }
        ioExecutor.execute {
            try {
                val body = JSONObject()
                    .put("cardId", request.cardId)
                    .put("lat", location?.latitude)
                    .put("lng", location?.longitude)
                    .put("accuracy", location?.accuracy?.toDouble())
                    .put("ticket", request.ticket)
                if (request.path != null) {
                    val payload = request.body?.let { JSONObject(it) }
                    if (location != null) payload?.put("location", JSONObject().put("lat", location.latitude).put("lng", location.longitude).put("accuracy", location.accuracy.toDouble()))
                    succeed(request.result, request(if (payload == null) "GET" else "POST", request.path, payload?.toString()))
                } else {
                    succeed(request.result, request("POST", "/api/v1/machines/login", body.toString()))
                }
            } catch (error: Exception) {
                mainHandler.post { request.result.error((error as? ApiException)?.code ?: "network_error", errorMessage(error), (error as? ApiException)?.let { mapOf("statusCode" to it.statusCode) }) }
            }
        }
    }

    private fun hasLocationPermission(): Boolean {
        val fine = activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        val coarse = activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    private fun cancelLocationRequest() {
        locationListener?.let {
            try {
                locationManager.removeUpdates(it)
            } catch (_: SecurityException) {
                // Permission may have been revoked while the request was active.
            }
        }
        locationListener = null
        locationTimeout?.let(mainHandler::removeCallbacks)
        locationTimeout = null
    }

    private fun request(method: String, path: String, body: String? = null): String {
        require(path.startsWith("/api/v1/") && !path.contains("..")) { "Invalid API path" }
        val url = URL(BASE_URL + path)
        val connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 15_000
        connection.readTimeout = 35_000
        connection.useCaches = false
        connection.setRequestProperty("Accept", "application/json")
        val uri = URI(url.toString())
        val cookies = cookieManager.cookieStore.get(uri)
        if (cookies.isNotEmpty()) {
            connection.setRequestProperty(
                "Cookie",
                cookies.joinToString("; ") { "${it.name}=${it.value}" },
            )
        }
        if (body != null) {
            connection.doOutput = true
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { output ->
                output.write(body.toByteArray(StandardCharsets.UTF_8))
            }
        }
        val status = connection.responseCode
        try {
            cookieManager.put(uri, connection.headerFields)
        } catch (_: Exception) {
            // A malformed provider cookie must not hide the HTTP response.
        }
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val responseBody = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
        connection.disconnect()
        if (status !in 200..299) {
            val message = runCatching { JSONObject(responseBody).optJSONObject("error")?.optString("message") }
                .getOrNull()
                ?.takeIf { it.isNotBlank() }
                ?: "请求失败（$status）"
            throw ApiException(message, status, runCatching { JSONObject(responseBody).getJSONObject("error").getString("code") }.getOrNull())
        }
        return JSONObject(responseBody).getJSONObject("data").toString()
    }

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    private fun errorMessage(error: Exception): String {
        return when (error) {
            is ApiException -> error.message ?: "PRiSM 请求失败"
            else -> error.message?.takeIf { it.isNotBlank() } ?: "PRiSM 请求失败"
        }
    }

    private data class LoginRequest(
        val cardId: String,
        val ticket: String,
        val result: MethodChannel.Result,
        val path: String? = null,
        val body: String? = null,
    )

    private class ApiException(message: String, val statusCode: Int, val code: String? = null) : Exception(message)
}
