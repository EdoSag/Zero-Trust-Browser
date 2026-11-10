package dev.sagron.zerotrustbrowser

import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter

/** A page's print adapter that says when the print screen has closed. */
class TrackedPrintAdapter(
    private val inner: PrintDocumentAdapter,
    private val onDone: () -> Unit,
) : PrintDocumentAdapter() {
    override fun onStart() = inner.onStart()

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) = inner.onLayout(oldAttributes, newAttributes, cancellationSignal, callback, extras)

    override fun onWrite(
        pages: Array<out PageRange>,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback,
    ) = inner.onWrite(pages, destination, cancellationSignal, callback)

    override fun onFinish() {
        inner.onFinish()
        onDone()
    }
}
