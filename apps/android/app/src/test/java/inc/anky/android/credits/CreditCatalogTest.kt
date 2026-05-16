package inc.anky.android.credits

import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Offerings
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesTransactionException
import inc.anky.android.core.credits.CreditCatalog
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class CreditCatalogTest {
    @Test
    fun matchesIosCreditCurrencyOfferingAndProductOrder() {
        assertEquals("CRD", CreditCatalog.CurrencyCode)
        assertEquals("credits DEV", CreditCatalog.OfferingIdentifier)
        assertEquals(
            listOf(
                "inc.dev.anky.credits.22",
                "inc.dev.anky.credits.88_bonus_11",
                "inc.dev.anky.credits.333_bonus_88",
            ),
            CreditCatalog.ProductOrder,
        )
    }

    @Test
    fun mapsIosCreditProductTitlesAndUnknownProductsAfterKnownOnes() {
        assertEquals("22 credits", CreditCatalog.titleForProduct("inc.dev.anky.credits.22"))
        assertEquals("99 credits", CreditCatalog.titleForProduct("inc.dev.anky.credits.88_bonus_11"))
        assertEquals("421 credits", CreditCatalog.titleForProduct("inc.dev.anky.credits.333_bonus_88"))

        assertEquals(0, CreditCatalog.productRank("inc.dev.anky.credits.22"))
        assertEquals(1, CreditCatalog.productRank("inc.dev.anky.credits.88_bonus_11"))
        assertEquals(2, CreditCatalog.productRank("inc.dev.anky.credits.333_bonus_88"))
        assertTrue(CreditCatalog.productRank("unknown.android.product") > CreditCatalog.productRank("inc.dev.anky.credits.333_bonus_88"))
    }

    @Test
    fun selectsIosNamedOfferingBeforeFallingBackToCurrentOffering() {
        val current = offering("current")
        val named = offering(CreditCatalog.OfferingIdentifier)

        assertSame(
            named,
            CreditCatalog.selectOffering(Offerings(current, mapOf(CreditCatalog.OfferingIdentifier to named))),
        )
        assertSame(
            current,
            CreditCatalog.selectOffering(Offerings(current, mapOf("other" to named))),
        )
        assertNull(CreditCatalog.selectOffering(Offerings(null, emptyMap())))
    }

    @Test
    fun mapsUserCancelledPurchasesToIosSuccessStatus() {
        val cancelled = PurchasesTransactionException(
            PurchasesError(PurchasesErrorCode.PurchaseCancelledError, "cancelled"),
            true,
        )
        val failed = PurchasesTransactionException(
            PurchasesError(PurchasesErrorCode.StoreProblemError, "store problem"),
            false,
        )

        assertEquals("Credits updated.", CreditCatalog.purchaseFailureMessage(cancelled))
        assertEquals("Could not complete that credit purchase.", CreditCatalog.purchaseFailureMessage(failed))
        assertEquals("Could not complete that credit purchase.", CreditCatalog.purchaseFailureMessage(RuntimeException("boom")))
    }

    private fun offering(identifier: String): Offering =
        Offering(
            identifier,
            "test offering",
            emptyMap(),
            emptyList(),
        )
}
