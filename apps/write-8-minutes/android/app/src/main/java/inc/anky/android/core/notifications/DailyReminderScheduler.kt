package inc.anky.android.core.notifications

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

class DailyReminderScheduler(
    private val context: Context,
) {
    fun setEnabled(enabled: Boolean, reminderMinutes: Int = reminderMinutes()) {
        context.getSharedPreferences("anky-reminders", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("daily_reminder_enabled", enabled)
            .putInt("daily_reminder_minutes", reminderMinutes.coerceIn(0, 23 * 60 + 59))
            .apply()
        if (enabled) scheduleNext() else cancel()
    }

    fun setReminderMinutes(minutes: Int) {
        context.getSharedPreferences("anky-reminders", Context.MODE_PRIVATE)
            .edit()
            .putInt("daily_reminder_minutes", minutes.coerceIn(0, 23 * 60 + 59))
            .apply()
        if (isEnabled()) scheduleNext()
    }

    fun isEnabled(): Boolean =
        context.getSharedPreferences("anky-reminders", Context.MODE_PRIVATE)
            .getBoolean("daily_reminder_enabled", false)

    private fun reminderMinutes(): Int =
        context.getSharedPreferences("anky-reminders", Context.MODE_PRIVATE)
            .getInt("daily_reminder_minutes", 9 * 60)

    private fun scheduleNext() {
        ensureChannel()
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent())
        alarmManager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextReminderEpochMs(),
            AlarmManager.INTERVAL_DAY,
            pendingIntent(),
        )
    }

    private fun cancel() {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent())
    }

    private fun pendingIntent(): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            8008,
            Intent(context, DailyReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun ensureChannel() {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ChannelId,
            "Anky reminders",
            NotificationManager.IMPORTANCE_DEFAULT,
        )
        manager.createNotificationChannel(channel)
    }

    private fun nextReminderEpochMs(): Long {
        val zone = ZoneId.systemDefault()
        val now = LocalDateTime.now(zone).truncatedTo(ChronoUnit.MINUTES)
        val reminderMinutes = reminderMinutes().coerceIn(0, 23 * 60 + 59)
        val today = now.toLocalDate().atTime(reminderMinutes / 60, reminderMinutes % 60)
        val next = if (today.isAfter(now)) today else today.plusDays(1)
        return next.atZone(zone).toInstant().toEpochMilli()
    }

    companion object {
        const val ChannelId = "anky_daily_reminders"
    }
}
