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
        assertEquals("Credits", CreditCatalog.OfferingIdentifier)
        assertEquals(
            listOf(
                "inc.anky.credits.3",
                "inc.anky.credits.11",
                "inc.anky.credits.33",
            ),
            CreditCatalog.ProductOrder,
        )
    }

    @Test
    fun mapsIosCreditProductTitlesAndUnknownProductsAfterKnownOnes() {
        assertEquals("3 reflections", CreditCatalog.titleForProduct("inc.anky.credits.3"))
        assertEquals("11 reflections", CreditCatalog.titleForProduct("inc.anky.credits.11"))
        assertEquals("33 reflections", CreditCatalog.titleForProduct("inc.anky.credits.33"))
        assertNull(CreditCatalog.subtitleForProduct("inc.anky.credits.3"))
        assertEquals("Stay with it", CreditCatalog.subtitleForProduct("inc.anky.credits.11"))
        assertEquals("Daily practice", CreditCatalog.subtitleForProduct("inc.anky.credits.33"))

        assertEquals(0, CreditCatalog.productRank("inc.anky.credits.3"))
        assertEquals(1, CreditCatalog.productRank("inc.anky.credits.11"))
        assertEquals(2, CreditCatalog.productRank("inc.anky.credits.33"))
        assertTrue(CreditCatalog.productRank("unknown.android.product") > CreditCatalog.productRank("inc.anky.credits.33"))
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

    @Test
    fun restoreCopyIsScopedToCurrentAnkyIdentity() {
        assertEquals("Purchases restored for this Anky identity.", CreditCatalog.RestoreSuccessMessage)
        assertEquals("Could not restore purchases for this Anky identity.", CreditCatalog.RestoreFailureMessage)
        assertTrue(CreditCatalog.RestoreIdentityNote.contains("Anky address"))
        assertTrue(CreditCatalog.RestoreIdentityNote.contains("Spent credits may not reappear"))
    }

    private fun offering(identifier: String): Offering =
        Offering(
            identifier,
            "test offering",
            emptyMap(),
            emptyList(),
        )
}
