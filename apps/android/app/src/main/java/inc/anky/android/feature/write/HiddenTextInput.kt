package inc.anky.android.feature.write

import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalTextToolbar
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.TextToolbar
import androidx.compose.ui.platform.TextToolbarStatus
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.TextFieldValue
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
    var resetToken by remember { mutableIntStateOf(0) }
    val value = remember { mutableStateOf(hiddenInputValue(resetToken)) }
    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val view = LocalView.current
    val focusManager = LocalFocusManager.current
    val disabledTextToolbar = remember { DisabledTextToolbar }
    fun showWritingKeyboard() {
        focusRequester.requestFocus()
        keyboard?.show()
        view.post {
            val inputMethodManager = view.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        }
    }
    fun hideWritingKeyboard() {
        keyboard?.hide()
        focusManager.clearFocus(force = true)
        view.post {
            val inputMethodManager = view.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.hideSoftInputFromWindow(view.windowToken, 0)
        }
    }
    fun resetBuffer() {
        resetToken += 1
        value.value = hiddenInputValue(resetToken)
    }

    CompositionLocalProvider(LocalTextToolbar provides disabledTextToolbar) {
        BasicTextField(
            value = value.value,
            onValueChange = { next ->
                if (!inputEnabled) return@BasicTextField
                val glyphs = next.text
                    .filterNot { it == HiddenInputAnchor }
                    .map { it.toString() }
                when {
                    glyphs.isEmpty() -> onRejectedMutation()
                    glyphs.all { it.isSingleProtocolGlyph() } -> {
                        if (glyphs.size == 1) {
                            onGlyph(glyphs.single())
                        } else {
                            onGlyphs(glyphs)
                        }
                    }
                    else -> onRejectedMutation()
                }
                resetBuffer()
            },
            modifier = modifier
                .focusRequester(focusRequester)
                .pointerInput(inputEnabled) {
                    detectTapGestures {
                        if (!inputEnabled) return@detectTapGestures
                        showWritingKeyboard()
                    }
                },
            enabled = inputEnabled,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.None,
            ),
            keyboardActions = KeyboardActions(
                onDone = {
                    showWritingKeyboard()
                },
            ),
            textStyle = TextStyle(color = Color.Transparent),
            singleLine = false,
        )
    }

    LaunchedEffect(inputEnabled, focusRequestId) {
        if (!inputEnabled) {
            resetBuffer()
            hideWritingKeyboard()
            return@LaunchedEffect
        }
        resetBuffer()
        showWritingKeyboard()
    }
}

private const val HiddenInputAnchor: Char = '\u2060'

private fun hiddenInputValue(token: Int): TextFieldValue {
    val text = HiddenInputAnchor.toString().repeat(if (token % 2 == 0) 1 else 2)
    return TextFieldValue(text = text, selection = TextRange(text.length))
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
