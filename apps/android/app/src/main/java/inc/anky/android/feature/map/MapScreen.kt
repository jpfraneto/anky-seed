package inc.anky.android.feature.map

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun MapScreen(
    viewModel: MapViewModel,
    onOpenReveal: (String) -> Unit,
) {
    LaunchedEffect(Unit) { viewModel.refresh() }
    val state = viewModel.state.collectAsStateWithLifecycle().value
    val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy").withZone(ZoneId.systemDefault())

    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(16.dp).testTag("map-screen"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.days.isEmpty()) {
            item { Text("No local ankys yet.") }
        }
        state.days.forEach { day ->
            item {
                Text(
                    formatter.format(Instant.ofEpochMilli(day.dayEpochMs)),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
            items(day.sessions, key = { it.hash }) { session ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenReveal(session.hash) }
                        .padding(vertical = 10.dp)
                        .testTag("map-session"),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(session.title, style = MaterialTheme.typography.bodyLarge)
                        Text(if (session.isComplete) "complete" else "fragment")
                    }
                    Text(session.preview, style = MaterialTheme.typography.bodySmall)
                    if (session.hasReflection) Text("saved reflection", style = MaterialTheme.typography.labelSmall)
                }
                HorizontalDivider()
            }
        }
    }
}
