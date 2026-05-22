# anky browser

This is the smallest browser client for Anky.

When the extension is enabled and the writer opens `x.com`, the page becomes a single Anky composer on a black field. The rest of X is covered. Press `Escape` to leave the wrapper for the current page session. Refreshing the page starts the wrapper again.

Clicking the `anky` extension button opens `x.com/home` when the current tab is somewhere else. On an existing X tab, it injects and re-activates the wrapper.

The content script records a local `.anky` draft while the writer types in the post box:

```txt
<starting_epoch_ms> <first_character>
<delta_ms> <next_character>
```

After 9 seconds of continuous writing, with no pause longer than 1.5 seconds, the page enters `anky` writing mode. The only visible change is a quieter gold edge on the composer.

The draft is stored locally through extension storage under:

- `anky.browser.activeDraft`
- `anky.browser.lastDraft`

The extension makes no network request while writing. Clicking `Post` opens X's post intent with the written text.

## Install

1. Open `chrome://extensions`.
2. Enable developer mode.
3. Load unpacked extension from this directory:

```txt
/Users/kithkui/anky/apps/browser
```

After local changes, click the reload button for `anky` on `chrome://extensions`, then refresh X or click the extension button.

## Files

- `manifest.json` declares the extension and X host access.
- `background.js` handles the extension button.
- `content.css` removes the X surface and frames the composer.
- `content.js` finds the composer, handles `Escape`, blocks paste/delete noise, and records the `.anky` stream.
