PROJECT_NAME ?= anky-landing
BRANCH ?= main
DIST_DIR ?= dist
WRANGLER ?= bunx wrangler

.PHONY: lint build deploy preview clean

lint:
	bun run lint

build:
	bun run build

deploy: build
	$(WRANGLER) pages deploy $(DIST_DIR) --project-name $(PROJECT_NAME) --branch $(BRANCH) --commit-dirty=true

preview: build
	bun run preview

clean:
	rm -rf $(DIST_DIR)
