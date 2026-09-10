package moe.neri.hinatago

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

/** Native ArcadeLink session, Passkey, card and location bridge for Android. */
class ArcadeLinkNativeBridge(private val activity: Activity) {
    companion object {
        const val CHANNEL = "moe.neri.hinatago/arcadelink_native"
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
            fail(result, "bridge_unavailable", "ArcadeLink 服务不可用")
            return
        }
        when (call.method) {
            "authenticatePasskey" -> authenticatePasskey(result)
            "cards" -> loadCards(result)
            "loginMachine" -> loginMachine(call, result)
            else -> result.notImplemented()
        }
    }

    private fun authenticatePasskey(result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val optionsJson = request("GET", "/api/auth/passkey/options")
                val request = GetCredentialRequest(
                    listOf(GetPublicKeyCredentialOption(optionsJson)),
                )
                mainHandler.post {
                    if (disposed) {
                        fail(result, "bridge_unavailable", "ArcadeLink 服务不可用")
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
                fail(result, "arcadelink_error", errorMessage(error))
            }
        }
    }

    private fun submitPasskey(assertionJson: String, result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                request(
                    "POST",
                    "/api/auth/passkey",
                    assertionJson,
                )
                succeed(result, null)
            } catch (error: Exception) {
                fail(result, "arcadelink_error", errorMessage(error))
            }
        }
    }

    private fun loadCards(result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                val body = JSONObject(request("GET", "/api/cards"))
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
                fail(result, "arcadelink_error", errorMessage(error))
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
        if (lastKnown != null && System.currentTimeMillis() - lastKnown.time < 5 * 60 * 1000) {
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

    private fun performMachineLogin(request: LoginRequest, location: Location) {
        mainHandler.post { channel?.invokeMethod("machineLoginSending", null) }
        ioExecutor.execute {
            try {
                val body = JSONObject()
                    .put("cardId", request.cardId)
                    .put("lat", location.latitude)
                    .put("lng", location.longitude)
                    .put("accuracy", location.accuracy.toDouble())
                    .put("ticket", request.ticket)
                request("POST", "/api/machines/login", body.toString())
                succeed(request.result, null)
            } catch (error: Exception) {
                fail(request.result, "arcadelink_error", errorMessage(error))
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
        val url = URL(BASE_URL + path)
        val connection = url.openConnection() as HttpURLConnection
        connection.requestMethod = method
        connection.connectTimeout = 15_000
        connection.readTimeout = 20_000
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
            val message = runCatching { JSONObject(responseBody).optString("error") }
                .getOrNull()
                ?.takeIf { it.isNotBlank() }
                ?: "请求失败（$status）"
            throw ApiException(message, status)
        }
        return responseBody
    }

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    private fun errorMessage(error: Exception): String {
        return when (error) {
            is ApiException -> error.message ?: "ArcadeLink 请求失败"
            else -> error.message?.takeIf { it.isNotBlank() } ?: "ArcadeLink 请求失败"
        }
    }

    private data class LoginRequest(
        val cardId: String,
        val ticket: String,
        val result: MethodChannel.Result,
    )

    private class ApiException(message: String, val statusCode: Int) : Exception(message)
}
