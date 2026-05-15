# Anky Privacy Policy

Last updated: 2026-05-14

Privacy is the shape of Anky, not a feature added later.

Anky is a local-first writing app. The core artifact is the `.anky` file on your device. The app should let you write, save, revisit, export, import, and delete your writing without making a server the owner of your interior life.

## The private artifact

Your `.anky` writing is stored on your device by default. A saved `.anky` file contains the accepted writing stream and timing data for a session.

Anky computes a SHA-256 hash of the exact `.anky` bytes. The hash is for integrity. It is not encryption. If someone has the same `.anky` bytes, they can compute the same hash.

The local archive code is in [local archive](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/LocalAnkyArchive.swift). The parser and hash code are in [protocol](https://github.com/jpfraneto/anky-seed/tree/main/apps/ios/Anky/Core/Protocol).

## Local identity

Anky creates or imports a local recovery phrase, stores it in device secure storage, and derives the writing identity locally. The seed phrase is not sent to Anky.

The identity code is in [writer identity](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/WriterIdentityStore.swift) and [keychain storage](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Identity/KeychainClient.swift).

## When plaintext leaves the device

Writing, saving, hashing, reading the map, and keeping local backups do not require plaintext to leave your device.

Plaintext can leave the device when you choose an action that sends it somewhere: asking Anky for a reflection, exporting or sharing files, importing a backup from a place you chose, or contacting support with text you provide.

The reflection request code is in [reflection client](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Mirror/MirrorClient.swift). The local export and restore flow is in [backup importer](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Core/Storage/BackupImporter.swift) and [you page model](https://github.com/jpfraneto/anky-seed/blob/main/apps/ios/Anky/Features/You/YouViewModel.swift).

## Reflections

When you ask for a reflection, the app sends the saved `.anky` bytes to the configured mirror service. The mirror checks the hash, reconstructs readable text for processing, and returns a reflection.

The local app stores the returned reflection as a local sidecar. Reflections are optional. Writing is free and does not depend on reflections.

## Backups and deletion

Exports and backups can contain plaintext writing, reflections, and related local metadata. Keep them somewhere private.

Deleting local writing data removes local `.anky` files, local reflections, and the local session index from this app's storage area. It does not automatically delete backend records already created by optional processing.

## What this policy does not claim

Anky does not claim that hashes encrypt writing.

Anky does not claim anonymity. Timing, account identifiers, processing requests, purchases, and support requests can be linkable.

Anky does not claim optional processing is local-only. If you ask for a reflection, plaintext writing is sent for processing.

Anky does claim the default direction of the app is local-first: the `.anky` file belongs first to the person who wrote it.

## Contact

Questions, deletion requests, and privacy reports: jp@anky.app
