package `in`.youpi.invest.invoice

import `in`.youpi.invest.service.GoldTransactionEntity
import org.apache.pdfbox.pdmodel.PDDocument
import org.apache.pdfbox.pdmodel.PDPage
import org.apache.pdfbox.pdmodel.PDPageContentStream
import org.apache.pdfbox.pdmodel.common.PDRectangle
import org.apache.pdfbox.pdmodel.font.PDType1Font
import org.apache.pdfbox.pdmodel.graphics.image.PDImageXObject
import org.springframework.core.io.ClassPathResource
import org.springframework.stereotype.Service
import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Generates a downloadable PDF invoice for a completed gold BUY transaction.
 *
 * Format follows Augmont's own compliance requirement: invoice must state
 * purity and karat (we sell 24K, 99.9% pure MMTC-PAMP gold -- same claim
 * already shown in the app's "Security & Features" list), plus quantity,
 * amount, transaction ID, and date. Tax breakdown (CGST 1.5% + SGST 1.5%
 * = 3% total) mirrors the split shown in Augmont's own Buy webhook sample
 * ("taxSplit": [{"type":"CGST","taxPerc":"1.50"}, {"type":"SGST",...}]),
 * computed backward from the GST-inclusive totalAmount we already store.
 */
@Service
class InvoiceService {

    private val dateFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy, hh:mm a")
        .withZone(ZoneId.of("Asia/Kolkata"))

    companion object {
        private val TAX_RATE = BigDecimal("0.03")
        private val HALF_TAX_RATE = BigDecimal("0.015")
    }

    fun generateBuyInvoice(txn: GoldTransactionEntity, customerName: String): ByteArray {
        require(txn.txnType == "BUY") { "Invoice generation is only supported for BUY transactions" }

        val totalAmount = txn.amountInr
        val preTaxAmount = totalAmount.divide(BigDecimal.ONE.add(TAX_RATE), 2, RoundingMode.HALF_EVEN)
        val cgst = preTaxAmount.multiply(HALF_TAX_RATE).setScale(2, RoundingMode.HALF_EVEN)
        val sgst = cgst
        val invoiceNumber = txn.augmontInvoiceNumber ?: "YOUPI-INV-${txn.id}"

        PDDocument().use { doc ->
            val page = PDPage(PDRectangle.A4)
            doc.addPage(page)
            val margin = 50f
            var y = page.mediaBox.height - margin

            PDPageContentStream(doc, page).use { cs ->
                // ── Logo ──
                try {
                    val logoResource = ClassPathResource("static/augmont-logo.png")
                    if (logoResource.exists()) {
                        val logoImage = PDImageXObject.createFromByteArray(doc, logoResource.inputStream.readBytes(), "augmont-logo")
                        val logoWidth = 140f
                        val logoHeight = logoWidth * logoImage.height / logoImage.width
                        cs.drawImage(logoImage, margin, y - logoHeight, logoWidth, logoHeight)
                    }
                } catch (_: Exception) {
                    // Logo missing/unreadable -- invoice still generates without it.
                }

                // ── Title block (right-aligned) ──
                cs.beginText()
                cs.setFont(PDType1Font.HELVETICA_BOLD, 18f)
                cs.newLineAtOffset(page.mediaBox.width - margin - 140f, y - 10f)
                cs.showText("TAX INVOICE")
                cs.endText()

                y -= 70f

                cs.moveTo(margin, y)
                cs.lineTo(page.mediaBox.width - margin, y)
                cs.stroke()
                y -= 25f

                // ── Invoice meta ──
                fun row(label: String, value: String, bold: Boolean = false) {
                    cs.beginText()
                    cs.setFont(PDType1Font.HELVETICA_BOLD, 10f)
                    cs.newLineAtOffset(margin, y)
                    cs.showText(label)
                    cs.endText()
                    cs.beginText()
                    cs.setFont(if (bold) PDType1Font.HELVETICA_BOLD else PDType1Font.HELVETICA, 10f)
                    cs.newLineAtOffset(margin + 170f, y)
                    cs.showText(value)
                    cs.endText()
                    y -= 18f
                }

                row("Invoice Number:", invoiceNumber)
                row("Transaction ID:", txn.augmontTxnId ?: txn.id.toString())
                row("Date:", dateFormatter.format(txn.createdAt))
                row("Customer Name:", customerName)
                row("Product:", "Digital Gold (${txn.metalType})")
                row("Purity / Karat:", "24K, 99.9% Pure (MMTC-PAMP Certified)")
                // COMPLIANCE FIX: was "Augmont Goldtech Pvt. Ltd. -- SG Vaulted
                // & Insured" -- Augmont's own marketing Guidelines.docx (point
                // 4) explicitly says not to mention "Augmont" alongside
                // safety/vault/security language. Augmont's name is still
                // attributed elsewhere on this invoice (footer, "sourced and
                // fulfilled by") where it isn't paired with security wording.
                row("Vaulting Partner:", "SG Vaulted & Insured")

                y -= 15f
                cs.moveTo(margin, y)
                cs.lineTo(page.mediaBox.width - margin, y)
                cs.stroke()
                y -= 25f

                // ── Amount table header ──
                cs.beginText()
                cs.setFont(PDType1Font.HELVETICA_BOLD, 11f)
                cs.newLineAtOffset(margin, y)
                cs.showText("Description")
                cs.newLineAtOffset(280f, 0f)
                cs.showText("Quantity")
                cs.newLineAtOffset(90f, 0f)
                cs.showText("Rate/gram")
                cs.newLineAtOffset(90f, 0f)
                cs.showText("Amount")
                cs.endText()
                y -= 8f
                cs.moveTo(margin, y)
                cs.lineTo(page.mediaBox.width - margin, y)
                cs.stroke()
                y -= 20f

                cs.beginText()
                cs.setFont(PDType1Font.HELVETICA, 10f)
                cs.newLineAtOffset(margin, y)
                cs.showText("24K Digital Gold")
                cs.newLineAtOffset(280f, 0f)
                cs.showText("${txn.grams.setScale(4, RoundingMode.HALF_EVEN)} g")
                cs.newLineAtOffset(90f, 0f)
                cs.showText("Rs. ${txn.ratePerGram.setScale(2, RoundingMode.HALF_EVEN)}")
                cs.newLineAtOffset(90f, 0f)
                cs.showText("Rs. $preTaxAmount")
                cs.endText()
                y -= 30f

                cs.moveTo(margin, y)
                cs.lineTo(page.mediaBox.width - margin, y)
                cs.stroke()
                y -= 22f

                // ── Tax breakdown ──
                fun amountRow(label: String, amount: String, bold: Boolean = false) {
                    cs.beginText()
                    cs.setFont(if (bold) PDType1Font.HELVETICA_BOLD else PDType1Font.HELVETICA, 10f)
                    cs.newLineAtOffset(page.mediaBox.width - margin - 220f, y)
                    cs.showText(label)
                    cs.newLineAtOffset(150f, 0f)
                    cs.showText(amount)
                    cs.endText()
                    y -= 16f
                }

                amountRow("Taxable Amount:", "Rs. $preTaxAmount")
                amountRow("CGST (1.5%):", "Rs. $cgst")
                amountRow("SGST (1.5%):", "Rs. $sgst")
                y -= 4f
                cs.moveTo(page.mediaBox.width - margin - 220f, y + 8f)
                cs.lineTo(page.mediaBox.width - margin, y + 8f)
                cs.stroke()
                y -= 6f
                amountRow("Total Amount:", "Rs. $totalAmount", bold = true)

                y -= 40f
                cs.moveTo(margin, y)
                cs.lineTo(page.mediaBox.width - margin, y)
                cs.stroke()
                y -= 20f

                // ── Footer ──
                cs.beginText()
                cs.setFont(PDType1Font.HELVETICA_OBLIQUE, 8f)
                cs.newLineAtOffset(margin, y)
                cs.showText("Gold is sourced and fulfilled by Augmont Goldtech Pvt. Ltd. This invoice is system-generated and does not require a signature.")
                cs.endText()
                y -= 12f
                cs.beginText()
                cs.setFont(PDType1Font.HELVETICA_OBLIQUE, 8f)
                cs.newLineAtOffset(margin, y)
                cs.showText("Nexospendz Finothrive Private Limited -- YouPI")
                cs.endText()
            }

            val out = ByteArrayOutputStream()
            doc.save(out)
            return out.toByteArray()
        }
    }
}