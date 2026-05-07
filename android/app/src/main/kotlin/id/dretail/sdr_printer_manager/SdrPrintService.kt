package id.dretail.sdr_printer_manager

import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterInfo
import android.print.PrinterId
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import java.io.FileOutputStream
import java.util.ArrayList

class SdrPrintService : PrintService() {

    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession {
        return object : PrinterDiscoverySession() {
            override fun onStartPrinterDiscovery(priorityList: List<PrinterId>) {
                val printers = ArrayList<PrinterInfo>()
                val printerId = generatePrinterId("sdr_direct_printer")

                val capabilities = PrinterCapabilitiesInfo.Builder(printerId)
                    .addMediaSize(PrintAttributes.MediaSize.ISO_A6, true)
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
                    "SDR Direct Printer",
                    PrinterInfo.STATUS_IDLE
                )
                    .setCapabilities(capabilities)
                    .setDescription("dRetail — Cetak Struk via Bluetooth")
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
            // Ambil data dokumen PDF yang disiapkan oleh sistem Android
            val document = printJob.document
            val fileDescriptor: ParcelFileDescriptor? = document?.data

            if (fileDescriptor != null) {
                // Data tersedia - tandai selesai
                // Implementasi kirim ke Bluetooth akan ditambahkan di versi berikutnya
                printJob.complete()
            } else {
                printJob.complete()
            }
        } catch (e: Exception) {
            printJob.fail(e.message)
        }
    }
}
