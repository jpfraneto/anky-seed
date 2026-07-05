# WHO THIS DOCUMENT IS FOR

You are an agent reading this protocol because your mission is to code an Anky client: an interface for writing that captures forward-only keystrokes as the session itself, preserves the exact rhythm of the writer, and emits `.anky` files that other clients can parse, hash, and verify without trusting your implementation.

# THE ANKY PROTOCOL

---

## what this is

An `.anky` file is a minimal, hash-verifiable record of a forward-only writing rhythm.

It is not a journal schema. It is not metadata. It is not a transcript plus timing data.
It is the ordered stream of accepted writing events.

This specification defines:

- the canonical `.anky` file format
- how to parse writing events
- how to determine whether a session is a complete anky
- how to hash the exact bytes
- what must stay outside the canonical stream

This specification does not define identity, authorship, literary quality,
consciousness, interpretation, model output, or reflection content.

An `.anky` is determined only by the writing rhythm it contains.

---

## the atom

A writing session is a UTF-8 plain text file.

Each line is one accepted character event.

The first line stores the absolute Unix epoch millisecond of the first accepted
character plus the character payload.

Every later line stores the elapsed milliseconds since the previous accepted
character plus the character payload.

```text
{epoch_ms} {character_or_SPACE}
{delta_ms} {character_or_SPACE}
{delta_ms} {character_or_SPACE}
...
```

No summary. No side metadata. No author identity. No model output. No
interpretation. If it did not happen as an accepted writing character, it is not
in the canonical `.anky` stream.

---

## the three rules

**1. forward only.**
No backspace. No delete. No arrow-key edits. No enter. No paste. No replacement.
Only accepted characters that advance the text are recorded.

**2. the rhythm is part of the writing.**
The text is here. The pauses are here. The absolute beginning is here. The cadence
between accepted characters is encoded directly into the file.

**3. completion is arithmetic.**
A session is a complete anky when the accumulated writing deltas are at least
`480000ms`. Below that threshold, it is an unfinished or open writing session.

---

## format specification

### line 1

```text
{epoch_ms} {character_or_SPACE}
```

`epoch_ms` is the absolute Unix timestamp in milliseconds of the first accepted
character.

`character_or_SPACE` is the first accepted character payload. A typed space is
encoded as the exact ASCII token `SPACE`.

The delimiter is the first single ASCII space (`0x20`) after the number.

Example:

```text
1776098721818 w
```

This line answers: when did the writing stream begin?

### subsequent lines

```text
{delta_ms} {character_or_SPACE}
```

`delta_ms` is the elapsed milliseconds since the previous accepted character.
It is a variable-length non-negative integer.

These are structurally valid delta prefixes:

```text
42 h
0 h
16032 h
```

The delimiter is the first single ASCII space after the number. Everything after
that delimiter is the character payload token.

### the space character

A typed space is stored as the exact token:

```text
SPACE
```

The line for a typed space contains the delta, one delimiter space, and then the
five ASCII letters `SPACE`.

```text
301 SPACE
```

means: 301ms elapsed, then the space key was accepted.

Literal trailing-space payloads are not canonical:

```text
301  
```

That line must be rejected by compliant parsers before hashing.

### encoding

- the file is UTF-8 encoded
- line endings are LF (`\n`) only, never CRLF (`\r\n`)
- no byte order mark
- the canonical stream contains only accepted character event lines
- character payloads should be normalized by the client before capture if the
  client performs text normalization at all

---

## completion

An anky is determined arithmetically.

For line 1, the accepted writing duration is `0`.
For each later line, add `delta_ms` to the accumulated writing duration.

```text
accepted_writing_duration_ms = sum(delta_ms for all non-initial lines)
```

If `accepted_writing_duration_ms >= 480000`, the file represents a complete anky.

If `accepted_writing_duration_ms < 480000`, the file represents an unfinished or
open writing session.

Reflection eligibility, proof eligibility, or app-specific unlocks may depend on
this arithmetic threshold.

Client apps may still have ritual policy, such as an 8-second silence timeout.
That timeout is a UI/session policy. It is not a synthetic record inside the
primitive writing stream.

If a client resumes an unfinished session after an interruption, the first new
accepted character may be appended with delta `0` so non-writing interruption time
is not encoded into the writing rhythm.

---

## a small example

```text
1712345678000 h
204 e
187 l
143 l
198 o
301 SPACE
89 w
```

This reconstructs as:

```text
hello w
```

What this string preserves:

- the exact moment the session began
- every inter-character interval
- the fact that a real space was typed, represented unambiguously as `SPACE`

The text is not all that is here. The rhythm is here too.

---

## the hash

```text
session_hash = sha256(raw_utf8_bytes_of_the_canonical_file)
```

Hash the exact bytes of the canonical `.anky` file.

Do not normalize line endings before hashing.
Do not trim whitespace before hashing.
Do not hash reconstructed prose.
Do not hash parsed JSON.
Do not hash sidecar metadata.

The hash is the identity of the session. The filename may be the hash:

```text
{session_hash}.anky
```

Verification is offline and requires no authority:

```python
sha256(open(filepath, "rb").read()).hexdigest() == filepath.split("/")[-1].replace(".anky", "")
```

If this holds, the file bytes match the claimed hash. If it fails, the file bytes
have changed or the claimed hash is wrong.

---

## verification

The protocol supports three canonical checks.

**1. structural validity**
The file parses according to the format rules above: one opening epoch line,
zero or more delta-character lines, LF-only, no BOM, valid character payloads,
and no metadata records.

**2. integrity**
The SHA-256 hash of the raw UTF-8 bytes matches the expected hash.

**3. completion**
The accumulated writing deltas are at least `480000ms`.

The hash proves byte integrity. The arithmetic proves whether the encounter is a
complete anky. The stream does not prove who or what produced it.

---

## what the data reveals

Given only the `.anky` file, a reader can derive:

- exact session start time
- every inter-character interval
- accumulated writing duration
- pause patterns and hesitation points
- rhythm consistency across the session
- reconstructed text including typos and disfluencies

Given only the `.anky` file, a reader cannot determine:

- why any particular pause occurred
- who wrote it, without external linkage
- what meaning should be assigned to the rhythm

The silence between accepted characters is data. It is not commentary.

---

## capture compliance

A capture client is protocol-compliant only if it enforces:

- rejection of backspace, delete, arrow-key edits, enter, paste, replacement,
  and other canonical edit operations
- no synthetic content records
- literal storage of accepted characters, with typed spaces encoded as `SPACE`
- variable-length non-negative integer deltas
- local hash computation from exact canonical file bytes
- UTF-8 output with LF line endings
- no metadata, author identity, model output, interpretation, or reflection text
  inside the canonical `.anky` stream

A compliant client should also document its policy on autocorrect, text
substitution, IME composition, voice input, and accessibility input methods.

If any of these are permitted, they belong in derived metadata, not in the
canonical file.

---

## derived data

The `.anky` file is the sole canonical record. If it is lost, the session is lost.
If it exists, downstream artifacts can be regenerated from it.

Derived artifacts may live beside it:

```text
{hash}.anky
{hash}.reflection.md
{hash}.image.webp
{hash}.meta.json
{hash}.conversation.json
```

A sidecar can be deleted and rebuilt. The `.anky` file cannot.

Metadata is downstream. The writing is upstream.

---

## reference parser

```python
import hashlib
import os


FULL_ANKY_DURATION_MS = 480000
SPACE_TOKEN = "SPACE"


def parse_anky(filepath):
    with open(filepath, "rb") as f:
        raw = f.read()

    text = raw.decode("utf-8")
    if text.startswith("\ufeff"):
        raise ValueError("invalid anky: BOM is not allowed")
    if "\r" in text:
        raise ValueError("invalid anky: line endings must be LF only")

    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]

    if not lines:
        raise ValueError("invalid anky: needs at least one accepted character")

    records = []
    accumulated_ms = 0

    for index, line in enumerate(lines):
        sep = line.find(" ")
        if sep <= 0:
            raise ValueError(f"line {index + 1}: missing delimiter")

        number = line[:sep]
        token = line[sep + 1 :]

        if not number.isdigit():
            raise ValueError(f"line {index + 1}: invalid number")
        if len(number) > 1 and number.startswith("0"):
            raise ValueError(f"line {index + 1}: leading zeroes are not canonical")

        char = parse_payload(token, index + 1)
        value = int(number)

        if index == 0:
            epoch_ms = value
            records.append({"kind": "start", "ms": epoch_ms, "char": char})
        else:
            accumulated_ms += value
            records.append({"kind": "keystroke", "ms": value, "char": char})

    return {
        "records": records,
        "accepted_writing_duration_ms": accumulated_ms,
        "complete": accumulated_ms >= FULL_ANKY_DURATION_MS,
    }


def parse_payload(token, line_number):
    if token == SPACE_TOKEN:
        return " "
    if token == " ":
        raise ValueError(f"line {line_number}: spaces must be encoded as SPACE")
    if token == "":
        raise ValueError(f"line {line_number}: missing character payload")
    if len(token) != 1:
        raise ValueError(f"line {line_number}: payload must be one character or SPACE")
    if ord(token) <= 31 or ord(token) == 127:
        raise ValueError(f"line {line_number}: control characters are not accepted")
    return token


def reconstruct(parsed):
    return "".join(record["char"] for record in parsed["records"])


def verify(filepath):
    expected = os.path.basename(filepath).removesuffix(".anky")
    with open(filepath, "rb") as f:
        computed = hashlib.sha256(f.read()).hexdigest()
    return computed == expected
```

---

## longevity

The format is deliberately minimal so a file written today remains readable by
any parser written decades from now.

If this specification changes, new rules should be explicit. Existing canonical
files should never be reinterpreted.

Derived metadata may change. Client implementations may change. The file remains
what it was when it was written.

---

## the bottom line

A textarea. A stream. A file. A hash.

You write forward. You do not edit. The rhythm is preserved.

The encounter becomes bytes. The bytes become a hash.

*the writing is the seed. everything else is fruit.*
