SHARDS_BIN ?= `which shards`

run:
	$(SHARDS_BIN) run --error-trace --progress
