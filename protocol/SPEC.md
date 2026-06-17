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

A typed space is encoded as `SPACE`:

```txt
<delta_ms> SPACE
```

A legacy terminal silence line may appear at the end of older artifacts:

```txt
8000
```

The terminal line is a compatibility marker, not a character, and does not count toward completion.

## Duration

The first accepted character occurs at the starting epoch. Each subsequent writing delta advances elapsed writing time.

A complete Anky has at least `480000` milliseconds of accumulated writing deltas.

The legacy terminal silence line does not advance writing duration and cannot make an incomplete fragment complete.

Valid fragments may be under `480000` milliseconds and may omit the terminal silence line. Current clients should not append terminal silence to newly saved active sessions.

## Reconstruction

Readable text is derived by concatenating accepted characters in order. `SPACE` reconstructs to a literal space. Reconstructed text is a view of `.anky`, not a replacement canonical format.

## Hashing

The `.anky` hash is SHA-256 over exact UTF-8 bytes.

Do not normalize line endings, whitespace, Unicode, or JSON-wrap the artifact before hashing.
