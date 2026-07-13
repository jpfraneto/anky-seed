package inc.anky.android.core.gate.runtime

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import inc.anky.android.R
import inc.anky.android.feature.gate.ShieldActivity
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Android's ManagedSettings + DeviceActivityMonitor in one process: a
 * `specialUse` foreground service that watches UsageStats foreground
 * events (~800ms cadence while the screen is on, a slow reconcile beat
 * while it is off) and puts [ShieldActivity] in front of any blocked app
 * that surfaces while the gate is locked.
 *
 * All judgement is [GateWatcherPolicy] + the Phase-A reconciler; this class
 * only observes and executes. Runs exactly while the gate is armed
 * ([GateRuntimeController.shouldRun]) — including through unlock windows,
 * where its tick doubles as the relock belt-and-braces.
 */
class GateWatcherService : Service() {

    private lateinit var runtime: GateRuntime
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    @Volatile private var screenOn = true

    private var lastQueryEndMillis = 0L
    private var currentForegroundPackage: String? = null
    private var lastShieldLaunchPackage: String? = null
    private var lastShieldLaunchAtMillis = 0L

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> screenOn = true
                Intent.ACTION_SCREEN_OFF -> {
                    screenOn = false
                    // Whatever was foregrounded is now behind the lock screen.
                    currentForegroundPackage = null
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        runtime = GateRuntime(this)
        screenOn = (getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        ContextCompat.registerReceiver(
            this,
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        startInForeground()
        lastQueryEndMillis = System.currentTimeMillis()
        scope.launch { watchLoop() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        runCatching { unregisterReceiver(screenReceiver) }
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // MARK: - Loop

    private suspend fun watchLoop() {
        while (scope.isActive) {
            runCatching { tick() }
            delay(if (screenOn) PollIntervalMillis else ScreenOffIntervalMillis)
        }
    }

    private fun tick() {
        if (!GateRuntimeController.shouldRun(this)) {
            stopSelf()
            return
        }
        val now = Instant.now()
        val gateOff = runtime.gateSwitchStore.isGateOff

        // Belt-and-braces reconcile (iOS reconciler philosophy): an expired
        // unlock relocks here even if the exact alarm was swallowed. Only
        // rewrite state on disagreement so the tick stays quiet.
        if (GateWatcherPolicy.needsStateReconcile(gateOff, runtime.stateStore.load(), now)) {
            runtime.shieldPort.reconcileShield(now)
        }

        if (!screenOn) return
        pollForegroundPackage()

        val verdict = GateWatcherPolicy.verdict(
            foregroundPackage = currentForegroundPackage,
            blockedPackages = runtime.selectionStore.blockedPackages(),
            ownPackage = packageName,
            gateOff = gateOff,
            state = runtime.stateStore.load(),
            now = now,
        )
        if (verdict is GateWatcherPolicy.Verdict.LaunchShield) {
            val nowMillis = System.currentTimeMillis()
            if (
                GateWatcherPolicy.shouldLaunchAgain(
                    lastLaunchedPackage = lastShieldLaunchPackage,
                    lastLaunchAtMillis = lastShieldLaunchAtMillis,
                    packageName = verdict.packageName,
                    nowMillis = nowMillis,
                )
            ) {
                lastShieldLaunchPackage = verdict.packageName
                lastShieldLaunchAtMillis = nowMillis
                launchShield(verdict.packageName)
            }
        }
    }

    /**
     * Reads MOVE_TO_FOREGROUND events since the last poll and keeps the
     * latest package *sticky* across ticks: if the writer is inside a
     * blocked app when its unlock window expires, no new event fires — the
     * remembered package is what lets the relock shield them mid-scroll.
     */
    private fun pollForegroundPackage() {
        val usageStats = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val end = System.currentTimeMillis()
        val events = usageStats.queryEvents(lastQueryEndMillis, end)
        lastQueryEndMillis = end
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            @Suppress("DEPRECATION") // Same constant as ACTIVITY_RESUMED (API 29+); works on every level we ship.
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                currentForegroundPackage = event.packageName
            }
        }
    }

    private fun launchShield(blockedPackage: String) {
        val label = runtime.selectionStore.labelFor(blockedPackage)
        startActivity(ShieldActivity.intent(this, blockedPackage, label))
    }

    // MARK: - Foreground presence

    private fun startInForeground() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(
                ChannelId,
                getString(R.string.gate_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.gate_channel_description)
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, ChannelId)
            .setSmallIcon(R.drawable.ic_anky_notification)
            .setContentTitle(getString(R.string.gate_notification_title))
            .setContentText(getString(R.string.gate_notification_text))
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(contentIntent)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NotificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NotificationId, notification)
        }
    }

    companion object {
        const val ChannelId = "anky_gate"
        const val NotificationId = 4107
        const val PollIntervalMillis = 800L

        /** Nobody can open an app while the screen is off; the slow beat only serves the relock reconcile. */
        const val ScreenOffIntervalMillis = 15_000L
    }
}
