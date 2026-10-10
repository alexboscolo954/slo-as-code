SLOTH_VERSION := v0.16.0
PROM_VERSION  := 3.15.0
OS   := $(shell uname -s | tr A-Z a-z)
ARCH := $(shell uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

.PHONY: tools generate check test mutate drift verify up e2e down

tools: bin/sloth bin/promtool

bin/sloth:
	mkdir -p bin
	curl -sSfL -o $@ https://github.com/slok/sloth/releases/download/$(SLOTH_VERSION)/sloth-$(OS)-$(ARCH)
	chmod +x $@

bin/promtool:
	mkdir -p bin
	curl -sSfL https://github.com/prometheus/prometheus/releases/download/v$(PROM_VERSION)/prometheus-$(PROM_VERSION).$(OS)-$(ARCH).tar.gz \
	  | tar xz -C bin --strip-components=1 prometheus-$(PROM_VERSION).$(OS)-$(ARCH)/promtool

generate: tools ## slos/ -> rules/ (commit the result)
	bin/sloth generate --no-log -i slos -o rules

check: tools
	bin/promtool check rules rules/*.yaml
	bin/promtool check config demo/prometheus.yml

test: tools ## burn-rate alert unit tests
	bin/promtool test rules tests/*.test.yaml

mutate: tools ## the tests must catch deliberately broken SLOs
	tests/mutate.sh

drift: generate ## generated rules must match what is committed
	git diff --exit-code rules/

verify: drift check test mutate

up:
	docker compose up --build -d

e2e: up ## inject errors, expect a page in Alertmanager
	demo/e2e.sh

down:
	docker compose down -v
