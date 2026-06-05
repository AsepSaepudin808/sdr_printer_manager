package id.dretail.sdr_printer_manager

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SETTINGS_CHANNEL = "id.dretail.sdr_printer_manager/settings"
    private val PRINT_JOB_CHANNEL = "id.dretail.sdr_printer_manager/print_job"
    private val SERVICE_CHANNEL = "id.dretail.sdr_printer_manager/foreground_service"

    private var pendingPrintJobPath: String? = null
    private var pendingPrintJobName: String? = null
    private var printJobMethodChannel: MethodChannel? = null

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter("id.dretail.sdr_printer_manager.NEW_PRINT_JOB")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(printJobReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(printJobReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(printJobReceiver) } catch (_: Exception) {}
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
                        // Buka dialog sistem untuk exclude app dari battery optimization.
                        // Ini berbeda dari autostart manufacturer — ini AOSP standar.
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                            ).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback ke halaman umum battery optimization settings
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
                    // Flag acknowledgement untuk autostart manufacturer-specific.
                    // Autostart (Xiaomi/MIUI, Oppo, dll) tidak bisa dibaca via Android API,
                    // sehingga kita hanya simpan flag bahwa user sudah diarahkan ke settings.
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
                        // Coba buka halaman autostart khusus per manufacturer.
                        // Jika device tidak dikenali, fallback ke App Info.
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

    /**
     * Mencoba membuka halaman autostart khusus per manufacturer.
     * Setiap brand punya Activity berbeda yang tidak ada di AOSP.
     * Returns true jika berhasil membuka salah satu.
     */
    private fun tryOpenManufacturerAutoStart(): Boolean {
        val candidates = listOf(
            // Xiaomi / MIUI
            ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ),
            // Oppo / ColorOS
            ComponentName(
                "com.coloros.safecenter",
                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ),
            ComponentName(
                "com.oppo.safe",
                "com.oppo.safe.permission.startup.StartupAppListActivity"
            ),
            // Vivo / OriginOS
            ComponentName(
                "com.vivo.permissionmanager",
                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ),
            // Huawei / HarmonyOS
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ),
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ),
            // Samsung One UI
            ComponentName(
                "com.samsung.android.lool",
                "com.samsung.android.sm.ui.battery.BatteryActivity"
            ),
            // OnePlus / OxygenOS
            ComponentName(
                "com.oneplus.security",
                "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            ),
            // Asus / ZenUI
            ComponentName(
                "com.asus.mobilemanager",
                "com.asus.mobilemanager.autostart.AutoStartActivity"
            ),
            // Letv / LeEco
            ComponentName(
                "com.letv.android.letvsafe",
                "com.letv.android.letvsafe.AutobootManageActivity"
            ),
            // Meizu / Flyme
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
                // Intent ini tidak tersedia di device ini, lanjut ke berikutnya
            }
        }
        return false
    }
}