PREFIX ?= /usr/local

.PHONY: test lint check install

test:
	bash tests/run.sh

lint:
	bash -n bin/skill-set tests/run.sh tests/skill_set_tests.sh completions/skill-set.bash

check: lint test

install:
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 0755 bin/skill-set "$(DESTDIR)$(PREFIX)/bin/skill-set"
	ln -sf skill-set "$(DESTDIR)$(PREFIX)/bin/sklset"
	install -d "$(DESTDIR)$(PREFIX)/share/bash-completion/completions"
	install -m 0644 completions/skill-set.bash "$(DESTDIR)$(PREFIX)/share/bash-completion/completions/skill-set"
	ln -sf skill-set "$(DESTDIR)$(PREFIX)/share/bash-completion/completions/sklset"
	install -d "$(DESTDIR)$(PREFIX)/share/zsh/site-functions"
	install -m 0644 completions/_skill-set "$(DESTDIR)$(PREFIX)/share/zsh/site-functions/_skill-set"
