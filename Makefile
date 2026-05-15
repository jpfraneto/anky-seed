.PHONY: protocol-test mirror-dev mirror-test android-test android-build inspect

protocol-test:
	cd protocol/implementations/typescript && bun install && bun test

mirror-dev:
	cd services/mirror && bun install && bun run dev

mirror-test:
	cd services/mirror && bun install && bun test

android-test:
	cd apps/android && ./gradlew :app:test

android-build:
	cd apps/android && ./gradlew :app:assembleDebug

inspect:
	bun run scripts/inspect-anky.ts $(FILE)
