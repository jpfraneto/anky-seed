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

`delta_ms` is a non-negative base-10 integer. It is not zero-padded.

A typed space is encoded as `SPACE`:

```txt
<delta_ms> SPACE
```

A terminal stillness line may appear at the end of reflected artifacts:

```txt
<terminal_stillness_ms>
```

The terminal line is a bare positive integer with no character payload. `8000` is the legacy/default value. Current clients allow configured values from `1000` through `8000`. The terminal line is a reflection marker, not a character, and does not count toward completion.

Newline characters are not accepted writing characters. A session is reconstructed as one block of text.

## Duration

The first accepted character occurs at the starting epoch. Each subsequent writing delta advances elapsed writing time.

A complete Anky has at least `480000` milliseconds of accumulated writing deltas.

The terminal stillness line does not advance writing duration and cannot make an incomplete fragment complete.

Valid fragments may be under `480000` milliseconds and may omit the terminal stillness line. Clients may strip the terminal line when reopening an unreflected fragment for continuation; the next accepted character after reopening lands with a `0` delta.

## Reconstruction

Readable text is derived by concatenating accepted characters in order. `SPACE` reconstructs to a literal space. Reconstructed text is a view of `.anky`, not a replacement canonical format.

## Hashing

The `.anky` hash is SHA-256 over exact UTF-8 bytes.

Do not normalize line endings, whitespace, Unicode, or JSON-wrap the artifact before hashing.
