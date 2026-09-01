LISP ?= sbcl
PREFIX ?= /usr/local

.PHONY: all build test install clean

all: build

build: hm hm-expert

hm: hackmode-user.asd hackmode.lisp
	$(LISP) --non-interactive \
		--load hackmode-user.asd \
		--eval '(ql:quickload :hackmode-user)' \
		--eval "(sb-ext:save-lisp-and-die \"hm\" :toplevel 'hackmode-user:main :executable t :compression t)"

hm-expert: hm
	printf '%s\n' '#!/bin/sh' 'exec "$$(dirname "$$0")/hm" expert "$$@"' > $@
	chmod +x $@

test:
	$(LISP) --non-interactive \
		--load hackmode-user.asd \
		--eval '(ql:quickload :hackmode-user)' \
		--eval '(assert (find-package :lish))'

install: build
	install -Dm755 hm $(DESTDIR)$(PREFIX)/bin/hm
	install -Dm755 hm-expert $(DESTDIR)$(PREFIX)/bin/hm-expert

clean:
	rm -f hm hm-expert
