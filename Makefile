# AI coding sandbox — convenience targets.
#
#   make build   PROJECT=my-api TOOLS=claude,codex
#   make shell   PROJECT=my-api
#   make rebuild PROJECT=my-api TOOLS=claude
#   make clean   PROJECT=my-api
#
PROJECT ?= default
TOOLS   ?= claude
PATHV   ?= $(CURDIR)
NETWORK ?= bridge
HERE    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: build shell detach rebuild clean

build:
	"$(HERE)build-sandbox.sh" $(PROJECT) --tools $(TOOLS)

shell:
	"$(HERE)run-sandbox.sh" $(PROJECT) "$(PATHV)" --network $(NETWORK)

detach:
	"$(HERE)run-sandbox.sh" $(PROJECT) "$(PATHV)" --network $(NETWORK) --detach

rebuild:
	-docker rmi ai-sandbox:$(PROJECT) 2>/dev/null
	"$(HERE)build-sandbox.sh" $(PROJECT) --tools $(TOOLS) --no-cache

clean:
	-docker rmi ai-sandbox:$(PROJECT) 2>/dev/null
