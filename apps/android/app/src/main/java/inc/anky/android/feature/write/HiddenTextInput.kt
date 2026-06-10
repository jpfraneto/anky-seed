package inc.anky.android.feature.write

import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalTextToolbar
import androidx.compose.ui.platform.TextToolbar
import androidx.compose.ui.platform.TextToolbarStatus
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import inc.anky.android.core.protocol.isSingleProtocolGlyph

@Composable
fun HiddenTextInput(
    onGlyph: (String) -> Unit,
    onGlyphs: (List<String>) -> Unit,
    onRejectedMutation: () -> Unit,
    inputEnabled: Boolean = true,
    focusRequestId: Int = 0,
    modifier: Modifier = Modifier,
) {
    val value = remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val disabledTextToolbar = remember { DisabledTextToolbar }

    CompositionLocalProvider(LocalTextToolbar provides disabledTextToolbar) {
        BasicTextField(
            value = value.value,
            onValueChange = { next ->
                if (!inputEnabled) return@BasicTextField
                when {
                    next.isEmpty() -> onRejectedMutation()
                    next.isSingleProtocolGlyph() -> onGlyph(next)
                    else -> onRejectedMutation()
                }
                value.value = ""
            },
            modifier = modifier.focusRequester(focusRequester),
            enabled = inputEnabled,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Password,
            ),
            textStyle = TextStyle(color = Color.Transparent),
            singleLine = true,
        )
    }

    LaunchedEffect(inputEnabled, focusRequestId) {
        if (!inputEnabled) return@LaunchedEffect
        focusRequester.requestFocus()
        keyboard?.show()
    }
}

private object DisabledTextToolbar : TextToolbar {
    override val status: TextToolbarStatus = TextToolbarStatus.Hidden

    override fun hide() = Unit

    override fun showMenu(
        rect: Rect,
        onCopyRequested: (() -> Unit)?,
        onPasteRequested: (() -> Unit)?,
        onCutRequested: (() -> Unit)?,
        onSelectAllRequested: (() -> Unit)?,
    ) = Unit
}
