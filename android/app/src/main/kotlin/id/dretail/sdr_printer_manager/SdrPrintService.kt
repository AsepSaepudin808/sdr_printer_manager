package id.dretail.sdr_printer_manager

import android.content.Intent
import android.os.ParcelFileDescriptor
import android.print.PrintAttributes
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.ArrayList

class SdrPrintService : PrintService() {

    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession {
        return object : PrinterDiscoverySession() {
            override fun onStartPrinterDiscovery(priorityList: List<PrinterId>) {
                val printers = ArrayList<PrinterInfo>()
                val printerId = generatePrinterId("sdr_direct_printer")

                val capabilities = PrinterCapabilitiesInfo.Builder(printerId)
                    .addMediaSize(PrintAttributes.MediaSize("58mm_32", "58mm (32 karakter)", 2283, 11692), true)
                    .addMediaSize(PrintAttributes.MediaSize("58mm_48", "58mm (48 karakter)", 2283, 11692), false)
                    .addMediaSize(PrintAttributes.MediaSize("80mm_48", "80mm (48 karakter)", 3150, 11692), false)
                    .addMediaSize(PrintAttributes.MediaSize("100mm", "100mm", 3937, 11692), false)
                    .addMediaSize(PrintAttributes.MediaSize.ISO_A6, false)
                    .addMediaSize(PrintAttributes.MediaSize.ISO_A5, false)
                    .addResolution(
                        PrintAttributes.Resolution("203dpi", "SDR 203dpi", 203, 203),
                        true
                    )
                    .setColorModes(
                        PrintAttributes.COLOR_MODE_MONOCHROME,
                        PrintAttributes.COLOR_MODE_MONOCHROME
                    )
                    .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                    .build()

                val info = PrinterInfo.Builder(
                    printerId,
                    "dPrinter Mart Service",
                    PrinterInfo.STATUS_IDLE
                )
                    .setCapabilities(capabilities)
                    .setDescription("dPrinter Mart — Cetak Struk via Bluetooth")
                    .build()

                printers.add(info)
                addPrinters(printers)
            }

            override fun onStopPrinterDiscovery() {}
            override fun onValidatePrinters(printerIds: List<PrinterId>) {}
            override fun onStartPrinterStateTracking(printerId: PrinterId) {}
            override fun onStopPrinterStateTracking(printerId: PrinterId) {}
            override fun onDestroy() {}
        }
    }

    override fun onRequestCancelPrintJob(printJob: PrintJob) {
        printJob.cancel()
    }

    override fun onPrintJobQueued(printJob: PrintJob) {
        try {
            printJob.start()
            
            val document = printJob.document
            val fileDescriptor: ParcelFileDescriptor? = document?.data

            if (fileDescriptor != null) {
                val tempFile = File(cacheDir, "print_job_${System.currentTimeMillis()}.pdf")
                
                FileInputStream(fileDescriptor.fileDescriptor).use { input ->
                    FileOutputStream(tempFile).use { output ->
                        input.copyTo(output)
                    }
                }
                fileDescriptor.close()
                
                val intent = Intent("id.dretail.sdr_printer_manager.NEW_PRINT_JOB").apply {
                    setPackage(packageName)
                    putExtra("PRINT_JOB_FILE_PATH", tempFile.absolutePath)
                    putExtra("PRINT_JOB_NAME", printJob.info.label)
                }
                sendBroadcast(intent)
                
                printJob.complete()
            } else {
                printJob.fail("No document data found")
            }
        } catch (e: Exception) {
            Log.e("SdrPrintService", "Error processing print job", e)
            printJob.fail(e.message)
        }
    }
}
