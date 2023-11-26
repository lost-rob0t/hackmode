##
# Hackmode
#
# @file
# @version 0.1

LISP ?= sbcl

all: test

run:
	$(LISP) --load run.lisp

build:
	$(LISP)	--non-interactive \
		--load hackmode-user.asd \
		--eval '(ql:quickload :hackmode-user)' \
		--load 'hackmode.lisp' \
		--eval "(sb-ext:save-lisp-and-die \"hm\" :toplevel 'hackmode-user::main :executable t :compression t)"
install:
	cp hm /usr/local/bin

clean:
	rm -f hm
