package inc.anky.android.subscription

import inc.anky.android.core.subscription.EntitlementSnapshot
import inc.anky.android.core.subscription.EntitlementStore
import inc.anky.android.core.subscription.SubscriptionFunnelEvent
import inc.anky.android.core.subscription.SubscriptionPackage
import inc.anky.android.core.subscription.SubscriptionPeriodKind
import inc.anky.android.core.subscription.SubscriptionPurchaseOutcome
import inc.anky.android.core.subscription.SubscriptionStoreKind
import inc.anky.android.core.subscription.TrialReminderSync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class EntitlementStoreTest {
    private val prefs = FakeSharedPreferences()
    private val gateway = FakeSubscriptionGateway()
    private val backend = RecordingSubscriptionBackend()

    private val entitledSnapshot = EntitlementSnapshot(
        isEntitled = true,
        productId = "anky.yearly",
        store = SubscriptionStoreKind.PLAY_STORE,
        periodType = SubscriptionPeriodKind.TRIAL,
        expirationDateMillis = 1_750_000_000_000L,
    )

    private val yearlyPackage = SubscriptionPackage(
        productId = "anky.yearly",
        priceAmountMicros = 88_000_000L,
        priceCurrencyCode = "USD",
        priceFormatted = "$88.00",
        hasFreeTrialOffer = true,
    )

    private fun store(
        scope: CoroutineScope,
        ignoresEntitlementForQA: Boolean = false,
        trialReminder: TrialReminderSync? = null,
    ) = EntitlementStore(
        gateway = gateway,
        backend = backend,
        preferences = prefs,
        scope = scope,
        trialReminder = trialReminder,
        ignoresEntitlementForQA = ignoresEntitlementForQA,
    )

    @Test
    fun qaOverrideMustShipOff() {
        assertFalse(EntitlementStore.IGNORES_ENTITLEMENT_FOR_QA)
    }

    @Test
    fun qaOverrideFiltersGatingButNotTruth() = runTest {
        val store = store(this, ignoresEntitlementForQA = true)

        store.applyCustomerInfo(entitledSnapshot)

        assertTrue(store.state.value.isEntitled)
        assertFalse(store.isEntitledForGating)
        // The persisted snapshot respects the QA override like every gate.
        assertTrue(prefs.getBoolean(EntitlementStore.WAS_ENTITLED_KEY, false))
        assertFalse(EntitlementStore.lastKnownEntitledForGating(prefs, ignoresEntitlementForQA = true))
        advanceUntilIdle()
    }

    @Test
    fun entitlementTruthDerivesEveryPublishedField() = runTest {
        val store = store(this)

        store.applyCustomerInfo(entitledSnapshot)
        advanceUntilIdle()

        with(store.state.value) {
            assertTrue(isEntitled)
            assertEquals("anky.yearly", activeProductId)
            assertEquals(SubscriptionStoreKind.PLAY_STORE, activeStore)
            assertEquals(SubscriptionPeriodKind.TRIAL, activePeriodType)
            assertEquals(1_750_000_000_000L, activeExpirationDateMillis)
            assertFalse(isPromotionalEntitlement)
            assertTrue(isInIntroTrial)
        }
        assertTrue(store.isEntitledForGating)

        store.applyCustomerInfo(EntitlementSnapshot.NOT_ENTITLED)
        advanceUntilIdle()

        with(store.state.value) {
            assertFalse(isEntitled)
            assertNull(activeProductId)
            assertNull(activeStore)
            assertNull(activePeriodType)
            assertNull(activeExpirationDateMillis)
        }
    }

    @Test
    fun promotionalGrantIsMarkedComplimentary() = runTest {
        val store = store(this)

        store.applyCustomerInfo(
            entitledSnapshot.copy(store = SubscriptionStoreKind.PROMOTIONAL, expirationDateMillis = null),
        )
        advanceUntilIdle()

        assertTrue(store.state.value.isPromotionalEntitlement)
        // Open-ended promotional grants stay entitled without an expiration.
        assertTrue(store.state.value.isEntitled)
        assertNull(store.state.value.activeExpirationDateMillis)
    }

    @Test
    fun lastKnownEntitledPersistsAcrossStores() = runTest {
        val store = store(this)

        store.applyCustomerInfo(entitledSnapshot)
        advanceUntilIdle()
        assertTrue(EntitlementStore.lastKnownEntitledForGating(prefs))

        store.applyCustomerInfo(EntitlementSnapshot.NOT_ENTITLED)
        advanceUntilIdle()
        assertFalse(EntitlementStore.lastKnownEntitledForGating(prefs))
    }

    @Test
    fun lapseFunnelFiresExactlyOncePerNarrowing() = runTest {
        val store = store(this)

        store.applyCustomerInfo(entitledSnapshot)
        store.applyCustomerInfo(EntitlementSnapshot.NOT_ENTITLED)
        store.applyCustomerInfo(EntitlementSnapshot.NOT_ENTITLED)
        advanceUntilIdle()

        assertEquals(
            listOf(SubscriptionFunnelEvent.LAPSED to null),
            backend.funnelEvents,
        )
    }

    @Test
    fun purchaseAwaitsBackendIdentifyBeforeReturning() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.purchaseOutcome = SubscriptionPurchaseOutcome.Completed(entitledSnapshot)
        val store = store(this)

        val purchased = store.purchase(yearlyPackage, activity = null)

        // Race-safe pay → confirm: the server already knows by the time the
        // paywall's completion runs — gated work can start immediately.
        assertTrue(purchased)
        assertEquals(listOf("0xWALLET"), backend.identifiedUserIds)
        assertTrue(store.state.value.isEntitled)
        assertFalse(store.state.value.isPurchasing)
        advanceUntilIdle()
    }

    @Test
    fun cancelledPurchaseIsSilent() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.purchaseOutcome = SubscriptionPurchaseOutcome.Cancelled
        val store = store(this)

        val purchased = store.purchase(yearlyPackage, activity = null)
        advanceUntilIdle()

        assertFalse(purchased)
        assertNull(store.state.value.purchaseErrorLine)
        assertEquals(emptyList<String>(), backend.identifiedUserIds)
    }

    @Test
    fun failedPurchaseSetsOneQuietLine() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.purchaseOutcome = SubscriptionPurchaseOutcome.Failed
        val store = store(this)

        val purchased = store.purchase(yearlyPackage, activity = null)
        advanceUntilIdle()

        assertFalse(purchased)
        assertEquals(EntitlementStore.PURCHASE_FAILED_LINE, store.state.value.purchaseErrorLine)
    }

    @Test
    fun purchaseFailsClosedWhenIdentityIsUnavailable() = runTest {
        gateway.identifyAnswer = null
        val store = store(this)

        val purchased = store.purchase(yearlyPackage, activity = null)
        advanceUntilIdle()

        assertFalse(purchased)
        assertEquals(EntitlementStore.STORE_UNREACHABLE_LINE, store.state.value.purchaseErrorLine)
        assertFalse(gateway.calls.any { it.startsWith("purchase:") })
    }

    @Test
    fun ensureConfiguredRetriesIdentifyAtPointOfUse() = runTest {
        gateway.identifyAnswer = "0xWALLET"
        val store = store(this)

        assertTrue(store.ensureConfigured())
        advanceUntilIdle()

        assertEquals("0xWALLET", gateway.identifiedAppUserId)
        assertTrue(gateway.calls.contains("ensureIdentified"))
        assertTrue(gateway.calls.contains("observeCustomerInfo"))
    }

    @Test
    fun restoreReportsRestoredAndTellsTheBackend() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.restoreAnswer = entitledSnapshot
        val store = store(this)

        store.restore()
        advanceUntilIdle()

        assertEquals(EntitlementStore.RESTORE_SUCCESS_LINE, store.state.value.restoreStatusLine)
        assertTrue(backend.funnelEvents.contains(SubscriptionFunnelEvent.RESTORED to null))
        assertEquals(listOf("0xWALLET"), backend.identifiedUserIds)
        assertFalse(store.state.value.isRestoring)
    }

    @Test
    fun restoreWithNothingToRestoreSaysSo() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.restoreAnswer = EntitlementSnapshot.NOT_ENTITLED
        val store = store(this)

        store.restore()
        advanceUntilIdle()

        assertEquals(EntitlementStore.RESTORE_NOTHING_LINE, store.state.value.restoreStatusLine)
        assertEquals(emptyList<String>(), backend.identifiedUserIds)
    }

    @Test
    fun restoreFailureIsNeverSilent() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.restoreAnswer = null
        val store = store(this)

        store.restore()
        advanceUntilIdle()

        assertEquals(EntitlementStore.RESTORE_FAILED_LINE, store.state.value.restoreStatusLine)
    }

    @Test
    fun unreachableOfferingsSetTheErrorLineAndALaterLoadClearsIt() = runTest {
        gateway.identifiedAppUserId = "0xWALLET"
        gateway.loadPackagesThrows = true
        val store = store(this)

        store.loadPackages()
        assertEquals(EntitlementStore.STORE_UNREACHABLE_LINE, store.state.value.offeringsErrorLine)

        gateway.loadPackagesThrows = false
        gateway.packagesAnswer = listOf(yearlyPackage)
        store.loadPackages()
        advanceUntilIdle()

        assertNull(store.state.value.offeringsErrorLine)
        assertEquals(yearlyPackage, store.state.value.yearlyPackage)
    }

    @Test
    fun foregroundReconcileCancelsTheReminderWhenTheTrialIsGone() = runTest {
        val port = RecordingTrialReminderPort()
        val nowMillis = entitledSnapshot.expirationDateMillis!! - 72L * 60L * 60L * 1000L
        gateway.identifiedAppUserId = "0xWALLET"
        val store = store(this, trialReminder = TrialReminderSync(port, nowMillis = { nowMillis }))

        store.applyCustomerInfo(entitledSnapshot)
        assertEquals(1, port.scheduledAt.size)

        // Trial cancelled in Play settings: fresh truth arrives on foreground.
        gateway.fetchCurrentAnswer = EntitlementSnapshot.NOT_ENTITLED
        store.reconcileOnForeground()
        advanceUntilIdle()

        assertTrue(port.cancelCount >= 1)
        assertFalse(store.state.value.isEntitled)
    }
}
