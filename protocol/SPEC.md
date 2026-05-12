# `.anky` Protocol Specification

`.anky` is the canonical artifact of an ANKY writing session.

The protocol is line-based UTF-8 text.

## Lines

The first line contains:

```txt
<starting_epoch_ms> <first_accepted_character>
```

Subsequent writing lines contain:

```txt
<delta_ms> <accepted_character>
```

A terminal silence line closes the session:

```txt
8000
```

The terminal line is a duration marker, not a character.

## Duration

The first accepted character occurs at the starting epoch. Each subsequent delta advances elapsed ritual time. The terminal silence line advances elapsed ritual time by 8000 milliseconds.

A complete Anky is at least 480000 milliseconds.

Valid fragments may be under 480000 milliseconds and may omit the terminal silence line.

## Reconstruction

Readable text is derived by concatenating accepted characters in order. Reconstructed text is a view of `.anky`, not a replacement canonical format.

## Hashing

The `.anky` hash is SHA-256 over exact UTF-8 bytes.

Do not normalize line endings, whitespace, Unicode, or JSON-wrap the artifact before hashing.
