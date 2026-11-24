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

# MCP stdio server executable (hackmode-mcp:main).
build-mcp:
	$(LISP)	--non-interactive \
		--eval '(require :asdf)' \
		--eval '(asdf:load-asd (truename "source/hackmode-mcp/hackmode-mcp.asd"))' \
		--eval '(asdf:load-system :hackmode-mcp)' \
		--eval "(sb-ext:save-lisp-and-die \"hm-mcp\" :toplevel 'hackmode-mcp:main :executable t :compression t)"
install:
	cp hm /usr/local/bin

clean:
	rm -f hm

clean-mcp:
	rm -f hm-mcp
