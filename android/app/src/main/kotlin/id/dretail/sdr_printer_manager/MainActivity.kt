package id.dretail.sdr_printer_manager

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
                    val jobData = mapOf(
                        "path" to filePath,
                        "name" to jobName
                    )

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
            registerReceiver(printJobReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(printJobReceiver)
        } catch (e: Exception) {
            // Ignore
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "openPrintSettings") {
                try {
                    val intent = Intent(Settings.ACTION_PRINT_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("UNAVAILABLE", "Could not open print settings", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // Foreground Service control
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    try {
                        SdrForegroundService.start(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to start foreground service", null)
                    }
                }
                "stopService" -> {
                    try {
                        SdrForegroundService.stop(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ERROR", "Failed to stop foreground service", null)
                    }
                }
                "openBatteryOptimization" -> {
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("UNAVAILABLE", "Could not open battery settings", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        printJobMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINT_JOB_CHANNEL)
        printJobMethodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getPendingPrintJob") {
                if (pendingPrintJobPath != null) {
                    val jobData = mapOf(
                        "path" to pendingPrintJobPath,
                        "name" to pendingPrintJobName
                    )
                    result.success(jobData)
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
}
