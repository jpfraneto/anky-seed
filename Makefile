.PHONY: protocol-test mirror-dev mirror-test inspect

protocol-test:
	cd protocol/implementations/typescript && bun install && bun test

mirror-dev:
	cd services/mirror && bun install && bun run dev

mirror-test:
	cd services/mirror && bun install && bun test

inspect:
	bun run scripts/inspect-anky.ts $(FILE)
