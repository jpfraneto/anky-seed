package inc.anky.android.feature.write

import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import inc.anky.android.core.protocol.isSingleProtocolGlyph

@Composable
fun HiddenTextInput(
    onGlyph: (String) -> Unit,
    onRejectedMutation: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val value = remember { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current

    BasicTextField(
        value = value.value,
        onValueChange = { next ->
            when {
                next.isEmpty() -> onRejectedMutation()
                next.isSingleProtocolGlyph() -> onGlyph(next)
                else -> onRejectedMutation()
            }
            value.value = ""
        },
        modifier = modifier.focusRequester(focusRequester),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            keyboardType = KeyboardType.Text,
        ),
        textStyle = TextStyle(color = Color.Transparent),
        singleLine = true,
    )

    LaunchedEffect(Unit) {
        focusRequester.requestFocus()
        keyboard?.show()
    }
}
