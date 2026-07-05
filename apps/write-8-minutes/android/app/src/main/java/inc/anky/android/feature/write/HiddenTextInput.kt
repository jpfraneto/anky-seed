package inc.anky.android.feature.write

import android.content.Context
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setText
import androidx.compose.ui.viewinterop.AndroidView
import inc.anky.android.core.protocol.protocolGlyphsOrNull

@Composable
fun HiddenTextInput(
    onGlyphs: (List<String>) -> Unit,
    onRejectedMutation: () -> Unit,
    inputEnabled: Boolean = true,
    focusRequestId: Int = 0,
    modifier: Modifier = Modifier,
) {
    var inputView by remember { mutableStateOf<ForwardOnlyInputView?>(null) }

    fun showWritingKeyboard() {
        val view = inputView ?: return
        view.requestFocus()
        view.post {
            val inputMethodManager = view.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    fun hideWritingKeyboard() {
        val view = inputView ?: return
        view.clearFocus()
        view.post {
            val inputMethodManager = view.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            inputMethodManager.hideSoftInputFromWindow(view.windowToken, 0)
        }
    }

    AndroidView(
        factory = { context ->
            ForwardOnlyInputView(context).also { inputView = it }
        },
        update = { view ->
            view.onGlyphs = onGlyphs
            view.onRejectedMutation = onRejectedMutation
            view.inputEnabled = inputEnabled
            view.isEnabled = inputEnabled
            if (inputEnabled && view.isAttachedToWindow && !view.isFocused) {
                view.post { showWritingKeyboard() }
            }
        },
        modifier = modifier
            .pointerInput(inputEnabled) {
                detectTapGestures {
                    if (inputEnabled) showWritingKeyboard()
                }
            }
            .semantics {
                setText { text ->
                    val glyphs = text.text.protocolGlyphsOrNull(maxGlyphs = 1)
                    if (glyphs == null) {
                        onRejectedMutation()
                    } else {
                        onGlyphs(glyphs)
                    }
                    true
                }
            },
    )

    LaunchedEffect(inputEnabled, focusRequestId) {
        if (inputEnabled) {
            showWritingKeyboard()
        } else {
            hideWritingKeyboard()
        }
    }
}

private class ForwardOnlyInputView(context: Context) : View(context) {
    var onGlyphs: (List<String>) -> Unit = {}
    var onRejectedMutation: () -> Unit = {}
    var inputEnabled: Boolean = true
    private var composingText: String = ""
    private var pendingCommittedComposition: String? = null

    init {
        isFocusable = true
        isFocusableInTouchMode = true
    }

    override fun onCheckIsTextEditor(): Boolean = inputEnabled

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        outAttrs.inputType = InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD or
            InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
            InputType.TYPE_TEXT_FLAG_MULTI_LINE
        outAttrs.imeOptions = EditorInfo.IME_ACTION_NONE or
            EditorInfo.IME_FLAG_NO_EXTRACT_UI or
            EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING

        return object : BaseInputConnection(this, false) {
            override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
                val raw = text?.toString().orEmpty()
                val pendingComposition = pendingCommittedComposition
                if (raw.isNotEmpty() && (raw == composingText || raw == pendingComposition)) {
                    composingText = ""
                    pendingCommittedComposition = null
                    return true
                }
                composingText = ""
                pendingCommittedComposition = null
                acceptInput(raw)
                return true
            }

            override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
                val next = text?.toString().orEmpty()
                if (next.isEmpty()) {
                    rejectInput()
                    composingText = ""
                    pendingCommittedComposition = null
                    return true
                }
                val appended = when {
                    composingText.isEmpty() -> next
                    next.startsWith(composingText) -> next.substring(composingText.length)
                    else -> {
                        rejectInput()
                        composingText = next
                        pendingCommittedComposition = null
                        return true
                    }
                }
                if (appended.isNotEmpty()) acceptInput(appended)
                composingText = next
                pendingCommittedComposition = null
                return true
            }

            override fun finishComposingText(): Boolean {
                pendingCommittedComposition = composingText.takeIf { it.isNotEmpty() }
                composingText = ""
                return true
            }

            override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
                rejectInput()
                return true
            }

            override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean {
                rejectInput()
                return true
            }

            override fun performEditorAction(actionCode: Int): Boolean {
                rejectInput()
                return true
            }

            override fun sendKeyEvent(event: KeyEvent): Boolean {
                return handleKeyEvent(event)
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        handleKeyEvent(event)

    private fun handleKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return true
        if (event.keyCode == KeyEvent.KEYCODE_DEL || event.keyCode == KeyEvent.KEYCODE_ENTER) {
            rejectInput()
            return true
        }
        val character = event.unicodeChar.takeIf { it != 0 }?.let { String(Character.toChars(it)) }
        if (character == null) {
            rejectInput()
        } else {
            acceptInput(character)
        }
        return true
    }

    private fun acceptInput(raw: String) {
        if (!inputEnabled || raw.isEmpty()) return
        val glyphs = raw.protocolGlyphsOrNull(maxGlyphs = 1)
        if (glyphs == null) {
            rejectInput()
        } else {
            onGlyphs(glyphs)
        }
    }

    private fun rejectInput() {
        if (inputEnabled) onRejectedMutation()
    }
}
