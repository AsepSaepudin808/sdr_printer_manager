package id.dretail.sdr_printer_manager

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.ParcelUuid
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SETTINGS_CHANNEL = "id.dretail.sdr_printer_manager/settings"
    private val PRINT_JOB_CHANNEL = "id.dretail.sdr_printer_manager/print_job"
    private val SERVICE_CHANNEL = "id.dretail.sdr_printer_manager/foreground_service"
    private val BLUETOOTH_CHANNEL = "id.dretail.sdr_printer_manager/bluetooth"
    private val BLUETOOTH_EVENT_CHANNEL = "id.dretail.sdr_printer_manager/bluetooth_events"

    private var pendingPrintJobPath: String? = null
    private var pendingPrintJobName: String? = null
    private var printJobMethodChannel: MethodChannel? = null

    private var bluetoothEventSink: EventChannel.EventSink? = null
    private var pendingPairMac: String? = null
    private val defaultPin = "0000"
    private var bleScanner: BluetoothLeScanner? = null
    private var isBleScanning = false
    private val bleSeenMacs = mutableSetOf<String>()

    private val bleScanCallback = object : ScanCallback() {
        @SuppressLint("MissingPermission")
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val mac = device.address
            // Emit only new devices (deduplicate)
            if (!bleSeenMacs.contains(mac)) {
                bleSeenMacs.add(mac)
                emitDevice("found", mapOf(
                    "mac" to mac,
                    "name" to (device.name ?: "Unknown"),
                ))
            }
        }

        override fun onBatchScanResults(results: List<ScanResult>) {
            for (result in results) {
                val device = result.device
                val mac = device.address
                if (!bleSeenMacs.contains(mac)) {
                    bleSeenMacs.add(mac)
                    emitDevice("found", mapOf(
                        "mac" to mac,
                        "name" to (device.name ?: "Unknown"),
                    ))
                }
            }
        }

        override fun onScanFailed(errorCode: Int) {
            isBleScanning = false
        }
    }

    private val bluetoothAdapter: BluetoothAdapter? get() {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    private val printJobReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == "id.dretail.sdr_printer_manager.NEW_PRINT_JOB") {
                val filePath = intent.getStringExtra("PRINT_JOB_FILE_PATH")
                val jobName = intent.getStringExtra("PRINT_JOB_NAME")
                if (filePath != null) {
                    val jobData = mapOf("path" to filePath, "name" to jobName)
                    if (printJobMethodChannel != null) {
                        printJobMethodChannel?.invokeMethod("onNewPrintJob", jobData)
                    } else {
                        pendingPrintJobPath = filePath
                        pendingPrintJobName = jobName
                    }
                }
            }
        }
    }

    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val action = intent.action ?: return
            when (action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (device != null) {
                        emitDevice("found", mapOf(
                            "mac" to device.address,
                            "name" to (device.name ?: "Unknown"),
                        ))
                    }
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    emitEvent("discovery_finished", null)
                }
                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    val bondState = intent.getIntExtra(
                        BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR
                    )
                    if (device != null) {
                        emitDevice(
                            "bond_state",
                            mapOf(
                                "mac" to device.address,
                                "name" to (device.name ?: "Unknown"),
                                "state" to bondStateToString(bondState),
                                "paired" to (bondState == BluetoothDevice.BOND_BONDED),
                            ),
                        )
                        // Clear pending PIN state if bonding ended
                        if (bondState != BluetoothDevice.BOND_BONDING) {
                            pendingPairMac = null
                        }
                    }
                }
                // Auto-confirm PIN when the system requests pairing authentication
                BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                    val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (device != null && device.address == pendingPairMac) {
                        // Abort the system PIN dialog and set the PIN directly
                        abortBroadcast()
                        setPinOnDevice(device)
                    }
                }
            }
        }
    }

    private fun bondStateToString(state: Int): String = when (state) {
        BluetoothDevice.BOND_NONE -> "none"
        BluetoothDevice.BOND_BONDING -> "bonding"
        BluetoothDevice.BOND_BONDED -> "bonded"
        else -> "unknown"
    }

    private fun emitEvent(type: String, payload: Map<String, Any>?) {
        mainHandler.post {
            val data = if (payload != null) mapOf("type" to type) + payload else mapOf("type" to type)
            bluetoothEventSink?.success(data)
        }
    }

    private fun emitDevice(type: String, payload: Map<String, Any>) {
        emitEvent(type, payload)
    }

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Register print job receiver
        val filter = IntentFilter("id.dretail.sdr_printer_manager.NEW_PRINT_JOB")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(printJobReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(printJobReceiver, filter)
        }
        // Register Bluetooth discovery & PIN receivers ONCE — always listening
        val btFilter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothReceiver, btFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(bluetoothReceiver, btFilter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(printJobReceiver) } catch (_: Exception) {}
        try { stopDiscovery() } catch (_: Exception) {}
        try { unregisterReceiver(bluetoothReceiver) } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openPrintSettings") {
                    try {
                        startActivity(Intent(Settings.ACTION_PRINT_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Could not open print settings", null)
                    }
                } else if (call.method == "openBluetoothSettings") {
                    try {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Could not open Bluetooth settings", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startService" -> {
                        try {
                            SdrForegroundService.start(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "stopService" -> {
                        try {
                            SdrForegroundService.stop(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "openBatteryOptimization" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("UNAVAILABLE", "Could not open battery settings", null)
                            }
                        }
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "isAutoStartAcknowledged" -> {
                        val prefs: SharedPreferences =
                            getSharedPreferences("sdr_prefs", Context.MODE_PRIVATE)
                        result.success(prefs.getBoolean("autostart_acknowledged", false))
                    }
                    "setAutoStartAcknowledged" -> {
                        val prefs: SharedPreferences =
                            getSharedPreferences("sdr_prefs", Context.MODE_PRIVATE)
                        prefs.edit().putBoolean("autostart_acknowledged", true).apply()
                        result.success(true)
                    }
                    "openAutoStartSettings" -> {
                        val opened = tryOpenManufacturerAutoStart()
                        if (!opened) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                                ).apply {
                                    data = android.net.Uri.parse("package:$packageName")
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("UNAVAILABLE", "Could not open app settings", null)
                            }
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPairedDevices" -> {
                        result.success(getPairedDevicesList())
                    }
                    "startScan" -> {
                        try {
                            startDiscovery()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "stopScan" -> {
                        try {
                            stopDiscovery()
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "pairDevice" -> {
                        val mac = call.argument<String>("mac")
                        if (mac.isNullOrEmpty()) {
                            result.error("INVALID", "mac address required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val adapter = bluetoothAdapter
                            if (adapter == null || !adapter.isEnabled) {
                                result.error("DISABLED", "Bluetooth is off", null)
                                return@setMethodCallHandler
                            }
                            val device = adapter.getRemoteDevice(mac)
                            // Mark this MAC so the PIN broadcast receiver auto-enters "0000"
                            pendingPairMac = mac
                            val ok = device.createBond()
                            if (!ok) {
                                pendingPairMac = null
                            }
                            result.success(ok)
                        } catch (e: Exception) {
                            pendingPairMac = null
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "unpairDevice" -> {
                        val mac = call.argument<String>("mac")
                        if (mac.isNullOrEmpty()) {
                            result.error("INVALID", "mac address required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val adapter = bluetoothAdapter
                            if (adapter == null) {
                                result.error("UNAVAILABLE", "No Bluetooth adapter", null)
                                return@setMethodCallHandler
                            }
                            val device = adapter.getRemoteDevice(mac)
                            result.success(removeBond(device))
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, BLUETOOTH_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    bluetoothEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    bluetoothEventSink = null
                }
            })

        printJobMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, PRINT_JOB_CHANNEL
        )
        printJobMethodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingPrintJob") {
                if (pendingPrintJobPath != null) {
                    result.success(
                        mapOf("path" to pendingPrintJobPath, "name" to pendingPrintJobName)
                    )
                    pendingPrintJobPath = null
                    pendingPrintJobName = null
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getPairedDevicesList(): List<Map<String, String>> {
        val adapter = bluetoothAdapter ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()
        val result = mutableListOf<Map<String, String>>()
        for (device in adapter.bondedDevices) {
            val name = device.name ?: "Unknown"
            result.add(mapOf("mac" to device.address, "name" to name))
        }
        return result
    }

    @SuppressLint("MissingPermission")
    private fun startDiscovery() {
        val adapter = bluetoothAdapter ?: return
        if (!adapter.isEnabled) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (!locationManager.isLocationEnabled) {
                runOnUiThread {
                    Toast.makeText(
                        this,
                        "Aktifkan Lokasi di Pengaturan untuk memindai Bluetooth.",
                        Toast.LENGTH_LONG
                    ).show()
                }
                emitEvent("location_disabled", null)
                return
            }
        }

        stopDiscovery()

        bleSeenMacs.clear()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            bleScanner = adapter.bluetoothLeScanner
            if (bleScanner != null) {
                isBleScanning = true
                val settings = ScanSettings.Builder()
                    .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                    .setReportDelay(0)
                    .build()
                try {
                    bleScanner?.startScan(null, settings, bleScanCallback)
                    emitEvent("discovery_started", null)
                    return
                } catch (e: Exception) {
                    isBleScanning = false
                    bleScanner = null
                }
            }
        }

        adapter.cancelDiscovery()
        adapter.startDiscovery()
        emitEvent("discovery_started", null)
    }

    @SuppressLint("MissingPermission")
    private fun stopDiscovery() {
        // Stop BLE scan
        if (isBleScanning && bleScanner != null) {
            try {
                bleScanner?.stopScan(bleScanCallback)
            } catch (_: Exception) {}
            isBleScanning = false
        }

        // Stop classic discovery
        val adapter = bluetoothAdapter
        if (adapter != null && adapter.isDiscovering) {
            try {
                adapter.cancelDiscovery()
            } catch (_: Exception) {}
        }
    }

    private fun removeBond(device: BluetoothDevice): Boolean {
        return try {
            device.javaClass.getMethod("removeBond").invoke(device) as Boolean
        } catch (e: Exception) {
            false
        }
    }

    private fun setPinOnDevice(device: BluetoothDevice) {
        try {
            val pinBytes: Array<Byte> = defaultPin.toByteArray().map { it } .toTypedArray()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                device.javaClass.getMethod("setPin", Array<Byte>::class.java)
                    .invoke(device, pinBytes)
            } else {
                @Suppress("DEPRECATION")
                device.javaClass.getMethod("setPin", Array<Byte>::class.java)
                    .invoke(device, pinBytes)
            }
            device.javaClass.getMethod("confirmPairing", Boolean::class.javaPrimitiveType)
                .invoke(device, true)
        } catch (e: Exception) {
            try {
                @Suppress("DEPRECATION")
                val method = device.javaClass.getMethod("setPin", Array<Byte>::class.java)
                val pinBytesLegacy: Array<Byte> = defaultPin.toByteArray().map { it } .toTypedArray()
                @Suppress("DEPRECATION")
                method.invoke(device, pinBytesLegacy)
            } catch (e2: Exception) {
                runOnUiThread {
                    Toast.makeText(
                        this,
                        "PIN required. Enter $defaultPin when prompted.",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }

    private fun tryOpenManufacturerAutoStart(): Boolean {
        val candidates = listOf(
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ),
            ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity"
            ),
            ComponentName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            ),
            ComponentName(
                "com.asus.mobilemanager",
                "com.asus.mobilemanager.autostart.AutoStartActivity"
            ),
            ComponentName(
                "com.letv.android.letvsafe",
                "com.letv.android.letvsafe.AutobootManageActivity"
            ),
            ComponentName(
                "com.meizu.safe",
                "com.meizu.safe.permission.SmartBGActivity"
            ),
        )

        for (component in candidates) {
            try {
                val intent = Intent().apply {
                    this.component = component
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }
}
