package moe.neri.quick_usb

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private const val TAG = "QuickUsbPlugin"
private const val ACTION_USB_PERMISSION = "moe.neri.quick_usb.USB_PERMISSION"

private val pendingIntentFlag =
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
  } else {
    PendingIntent.FLAG_UPDATE_CURRENT
  }

private fun pendingPermissionIntent(context: Context) = PendingIntent.getBroadcast(context, 0, Intent(ACTION_USB_PERMISSION), pendingIntentFlag)

/** QuickUsbPlugin */
class QuickUsbPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private lateinit var deviceConnectionEventChannel: EventChannel

  private var applicationContext: Context? = null
  private var usbManager: UsbManager? = null

  // --- Background read state ---
  private var readExecutor: ExecutorService? = null
  private val isReading = AtomicBoolean(false)
  private var eventSink: EventChannel.EventSink? = null
  private var deviceConnectionEventSink: EventChannel.EventSink? = null
  private val mainHandler = Handler(Looper.getMainLooper())
  private var deviceConnectionReceiver: BroadcastReceiver? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "quick_usb")
    channel.setMethodCallHandler(this)
    applicationContext = flutterPluginBinding.applicationContext
    usbManager = applicationContext?.getSystemService(Context.USB_SERVICE) as UsbManager

    // EventChannel for streaming bulk transfer reads from background thread
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "quick_usb/bulk_transfer_in_stream")
    eventChannel.setStreamHandler(this)

    deviceConnectionEventChannel = EventChannel(
      flutterPluginBinding.binaryMessenger,
      "quick_usb/device_connection",
    )
    deviceConnectionEventChannel.setStreamHandler(DeviceConnectionStreamHandler())
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
    deviceConnectionEventChannel.setStreamHandler(null)
    stopBulkTransferInStream()
    unregisterDeviceConnectionReceiver()
    usbManager = null
    applicationContext = null
  }

  // --- EventChannel.StreamHandler ---

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    Log.d(TAG, "bulkTransferInStream: onListen")
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    Log.d(TAG, "bulkTransferInStream: onCancel")
    eventSink = null
    stopBulkTransferInStream()
  }

  private inner class DeviceConnectionStreamHandler : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
      deviceConnectionEventSink = events
      registerDeviceConnectionReceiver()
    }

    override fun onCancel(arguments: Any?) {
      deviceConnectionEventSink = null
      unregisterDeviceConnectionReceiver()
    }
  }

  private fun registerDeviceConnectionReceiver() {
    if (deviceConnectionReceiver != null) {
      return
    }

    val context = applicationContext ?: return
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        val device = extractUsbDevice(intent) ?: return
        val type = when (intent.action) {
          UsbManager.ACTION_USB_DEVICE_ATTACHED -> "attached"
          UsbManager.ACTION_USB_DEVICE_DETACHED -> "detached"
          else -> return
        }

        mainHandler.post {
          deviceConnectionEventSink?.success(
            mapOf(
              "type" to type,
              "device" to toDeviceMap(device),
            ),
          )
        }
      }
    }

    val filter = IntentFilter().apply {
      addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
      addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
    } else {
      context.registerReceiver(receiver, filter)
    }
    deviceConnectionReceiver = receiver
  }

  private fun unregisterDeviceConnectionReceiver() {
    val context = applicationContext ?: return
    val receiver = deviceConnectionReceiver ?: return
    try {
      context.unregisterReceiver(receiver)
    } catch (_: IllegalArgumentException) {
    }
    deviceConnectionReceiver = null
  }

  private fun extractUsbDevice(intent: Intent): UsbDevice? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
    } else {
      @Suppress("DEPRECATION")
      intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
    }
  }

  private fun toDeviceMap(device: UsbDevice) = mapOf(
    "identifier" to device.deviceName,
    "vendorId" to device.vendorId,
    "productId" to device.productId,
    "configurationCount" to device.configurationCount,
  )

  private fun toConfigurationMap(configuration: UsbConfiguration) = mapOf(
    "id" to configuration.id,
    "interfaces" to List(configuration.interfaceCount) {
      toInterfaceMap(configuration.getInterface(it))
    }
  )

  private fun toInterfaceMap(usbInterface: UsbInterface) = mapOf(
    "id" to usbInterface.id,
    "alternateSetting" to usbInterface.alternateSetting,
    "interfaceClass" to usbInterface.interfaceClass,
    "interfaceSubclass" to usbInterface.interfaceSubclass,
    "interfaceProtocol" to usbInterface.interfaceProtocol,
    "endpoints" to List(usbInterface.endpointCount) {
      toEndpointMap(usbInterface.getEndpoint(it))
    }
  )

  private fun toEndpointMap(endpoint: UsbEndpoint) = mapOf(
    "endpointNumber" to endpoint.endpointNumber,
    "direction" to endpoint.direction,
    "type" to endpoint.type,
    "maxPacketSize" to endpoint.maxPacketSize,
  )

  private fun findInterface(
    device: UsbDevice,
    id: Int,
    alternateSetting: Int,
  ): UsbInterface? {
    for (i in 0 until device.interfaceCount) {
      val usbInterface = device.getInterface(i)
      if (
        usbInterface.id == id &&
        usbInterface.alternateSetting == alternateSetting
      ) {
        return usbInterface
      }
    }
    return null
  }

  private fun findEndpoint(
    device: UsbDevice,
    endpointNumber: Int,
    direction: Int,
  ): UsbEndpoint? {
    for (i in 0 until device.interfaceCount) {
      val usbInterface = device.getInterface(i)
      for (j in 0 until usbInterface.endpointCount) {
        val endpoint = usbInterface.getEndpoint(j)
        if (
          endpoint.endpointNumber == endpointNumber &&
          endpoint.direction == direction
        ) {
          return endpoint
        }
      }
    }
    return null
  }

  private var usbDevice: UsbDevice? = null
  private var usbDeviceConnection: UsbDeviceConnection? = null

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "getDeviceList" -> {
        val manager = usbManager ?: return result.error("IllegalState", "usbManager null", null)
        val usbDeviceList = manager.deviceList.entries.map {
          mapOf(
            "identifier" to it.key,
            "vendorId" to it.value.vendorId,
            "productId" to it.value.productId,
            "configurationCount" to it.value.configurationCount,
          )
        }
        result.success(usbDeviceList)
      }
      "getDeviceDescription" -> {
        val context = applicationContext ?: return result.error("IllegalState", "applicationContext null", null)
        val manager = usbManager ?: return result.error("IllegalState", "usbManager null", null)
        val identifier = call.argument<Map<String, Any>>("device")!!["identifier"]!!;
        val device = manager.deviceList[identifier] ?: return result.error("IllegalState", "usbDevice null", null)
        val requestPermission = call.argument<Boolean>("requestPermission")!!;

        val hasPermission = manager.hasPermission(device)
        if (requestPermission && !hasPermission) {
          val permissionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
              context.unregisterReceiver(this)
              val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
              result.success(mapOf(
                "manufacturer" to device.manufacturerName,
                "product" to device.productName,
                "serialNumber" to if (granted) device.serialNumber else null,
              ))
            }
          }
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              context.registerReceiver(permissionReceiver, IntentFilter(ACTION_USB_PERMISSION),
                  Context.RECEIVER_EXPORTED)
          }else {
              context.registerReceiver(permissionReceiver, IntentFilter(ACTION_USB_PERMISSION));
          }
          manager.requestPermission(device, pendingPermissionIntent(context))
        } else {
          result.success(mapOf(
            "manufacturer" to device.manufacturerName,
            "product" to device.productName,
            "serialNumber" to if (hasPermission) device.serialNumber else null,
          ))
        }
      }
      "hasPermission" -> {
        val manager = usbManager ?: return result.error("IllegalState", "usbManager null", null)
        val identifier = call.argument<String>("identifier")
        val device = manager.deviceList[identifier]
        result.success(manager.hasPermission(device))
      }
      "requestPermission" -> {
        val context = applicationContext ?: return result.error("IllegalState", "applicationContext null", null)
        val manager = usbManager ?: return result.error("IllegalState", "usbManager null", null)
        val identifier = call.argument<String>("identifier")
        val device = manager.deviceList[identifier]
        if (manager.hasPermission(device)) {
          result.success(true)
        } else {
          val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
              context.unregisterReceiver(this)
              val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
              result.success(granted);
            }
          }
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
              context.registerReceiver(receiver, IntentFilter(ACTION_USB_PERMISSION),
                  Context.RECEIVER_EXPORTED)
          }else {
              context.registerReceiver(receiver, IntentFilter(ACTION_USB_PERMISSION));
          }
          manager.requestPermission(device, pendingPermissionIntent(context))
        }
      }
      "openDevice" -> {
        val manager = usbManager ?: return result.error("IllegalState", "usbManager null", null)
        val identifier = call.argument<String>("identifier")
        usbDevice = manager.deviceList[identifier]
        usbDeviceConnection = manager.openDevice(usbDevice)
        result.success(true)
      }
      "closeDevice" -> {
        stopBulkTransferInStream()
        usbDeviceConnection?.close()
        usbDeviceConnection = null
        usbDevice = null
        result.success(null)
      }
      "getConfiguration" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val index = call.argument<Int>("index")!!
        val configuration = device.getConfiguration(index)
        val map = toConfigurationMap(configuration) + ("index" to index)
        result.success(map)
      }
      "setConfiguration" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val connection = usbDeviceConnection ?: return result.error("IllegalState", "usbDeviceConnection null", null)
        val index = call.argument<Int>("index")!!
        val configuration = device.getConfiguration(index)
        result.success(connection.setConfiguration(configuration))
      }
      "claimInterface" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val connection = usbDeviceConnection ?: return result.error("IllegalState", "usbDeviceConnection null", null)
        val id = call.argument<Int>("id")!!
        val alternateSetting = call.argument<Int>("alternateSetting")!!
        val usbInterface = findInterface(device, id, alternateSetting)
        result.success(connection.claimInterface(usbInterface, true))
      }
      "releaseInterface" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val connection = usbDeviceConnection ?: return result.error("IllegalState", "usbDeviceConnection null", null)
        val id = call.argument<Int>("id")!!
        val alternateSetting = call.argument<Int>("alternateSetting")!!
        val usbInterface = findInterface(device, id, alternateSetting)
        result.success(connection.releaseInterface(usbInterface))
      }
      "bulkTransferIn" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val connection = usbDeviceConnection ?: return result.error(
          "IllegalState",
          "usbDeviceConnection null",
          null
        )
        val endpointMap = call.argument<Map<String, Any>>("endpoint")!!
        val maxLength = call.argument<Int>("maxLength")!!
        val endpoint =
          findEndpoint(
            device,
            endpointMap["endpointNumber"] as Int,
            endpointMap["direction"] as Int,
          )
        val timeout = call.argument<Int>("timeout")!!

        // TODO Check [UsbDeviceConnection.bulkTransfer] API >= 28
        require(maxLength <= MAX_USBFS_BUFFER_SIZE) { "Before 28, a value larger than 16384 bytes would be truncated down to 16384" }
        val buffer = ByteArray(maxLength)
        val actualLength = connection.bulkTransfer(endpoint, buffer, buffer.count(), timeout)
        if (actualLength < 0) {
          result.error("unknown", "bulkTransferIn error", null)
        } else {
          result.success(buffer.take(actualLength))
        }
      }
      "bulkTransferOut" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val connection = usbDeviceConnection ?: return result.error(
          "IllegalState",
          "usbDeviceConnection null",
          null
        )
        val endpointMap = call.argument<Map<String, Any>>("endpoint")!!
        val data = call.argument<ByteArray>("data")!!
        val timeout = call.argument<Int>("timeout")!!
        val endpoint =
          findEndpoint(
            device,
            endpointMap["endpointNumber"] as Int,
            endpointMap["direction"] as Int,
          )

        // TODO Check [UsbDeviceConnection.bulkTransfer] API >= 28
        val dataSplit = data.asList()
          .windowed(MAX_USBFS_BUFFER_SIZE, MAX_USBFS_BUFFER_SIZE, true)
          .map { it.toByteArray() }
        var sum: Int? = null
        for (bytes in dataSplit) {
          val actualLength = connection.bulkTransfer(endpoint, bytes, bytes.count(), timeout)
          if (actualLength < 0) break
          sum = (sum ?: 0) + actualLength
        }
        if (sum == null) {
          result.error("unknown", "bulkTransferOut error", null)
        } else {
          result.success(sum)
        }
      }
      // --- Streaming bulk transfer API ---
      "startBulkTransferInStream" -> {
        val device = usbDevice ?: return result.error("IllegalState", "usbDevice null", null)
        val connection = usbDeviceConnection ?: return result.error("IllegalState", "usbDeviceConnection null", null)
        val endpointMap = call.argument<Map<String, Any>>("endpoint")!!
        val maxLength = call.argument<Int>("maxLength") ?: 64
        val readTimeout = call.argument<Int>("timeout") ?: 50

        val endpoint = findEndpoint(
          device,
          endpointMap["endpointNumber"] as Int,
          endpointMap["direction"] as Int,
        )
        if (endpoint == null) {
          return result.error("INVALID_ENDPOINT", "Endpoint not found", null)
        }

        startBulkTransferInStream(connection, endpoint, maxLength, readTimeout)
        result.success(true)
      }
      "stopBulkTransferInStream" -> {
        stopBulkTransferInStream()
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  // --- Background read thread ---

  /**
   * Start a dedicated background thread that continuously calls bulkTransfer
   * and pushes received data to Flutter via EventChannel.
   *
   * This is the key performance optimization: USB reads no longer block the
   * Flutter UI thread. The background thread handles blocking I/O, and data
   * is posted to the main thread only when bytes are actually received.
   */
  private fun startBulkTransferInStream(
    connection: UsbDeviceConnection,
    endpoint: UsbEndpoint,
    maxLength: Int,
    timeout: Int,
  ) {
    if (isReading.getAndSet(true)) {
      Log.w(TAG, "bulkTransferInStream already running")
      return
    }

    readExecutor = Executors.newSingleThreadExecutor()
    readExecutor?.execute {
      Log.i(TAG, "Background bulk read loop started (ep=${endpoint.endpointNumber}, maxLen=$maxLength, timeout=$timeout)")
      val buffer = ByteArray(maxLength)

      while (isReading.get()) {
        try {
          val bytesRead = connection.bulkTransfer(endpoint, buffer, buffer.size, timeout)
          if (bytesRead > 0) {
            val data = buffer.copyOf(bytesRead)
            // Post to main thread for EventChannel delivery
            mainHandler.post {
              eventSink?.success(data.toList())
            }
          }
          // bytesRead <= 0 means timeout or no data, just continue
        } catch (e: Exception) {
          Log.e(TAG, "Bulk read error: ${e.message}")
          // Brief pause to avoid tight-looping on persistent errors
          try { Thread.sleep(5) } catch (_: InterruptedException) { break }
        }
      }
      Log.i(TAG, "Background bulk read loop stopped")
    }
  }

  private fun stopBulkTransferInStream() {
    if (isReading.getAndSet(false)) {
      Log.i(TAG, "Stopping bulk read stream")
    }
    readExecutor?.shutdownNow()
    readExecutor = null
  }

  private companion object {
    /** [UsbRequest.MAX_USBFS_BUFFER_SIZE] */
    private const val MAX_USBFS_BUFFER_SIZE = 16384
  }
}
