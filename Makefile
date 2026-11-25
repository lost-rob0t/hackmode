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
# Registering the hackmode asd family here (the CI job does the same):
# asdf cannot resolve :hackmode/:hackmode-database/:hackmode-provider-zap
# from the mcp asd alone (KB asdf_trap). External pinned deps (tek9,
# star-cl, star-lang) resolve through CL_SOURCE_REGISTRY and quicklisp
# local projects — see .prolog/kb/prolog_toolchain.pl for the local recipe.
# The ZAP daemon provider system is loaded so the declared zap tools
# resolve to live backends in the serving image; it talks to the daemon
# only at run time.
build-mcp:
	$(LISP)	--non-interactive \
		--eval '(require :asdf)' \
		--eval '(asdf:load-asd (truename "source/hackmode-core/hackmode.asd"))' \
		--eval '(asdf:load-asd (truename "source/hackmode-database/hackmode-database.asd"))' \
		--eval '(asdf:load-asd (truename "source/hackmode-starlang/hackmode-starlang.asd"))' \
		--eval '(asdf:load-asd (truename "source/hackmode-mcp/hackmode-mcp.asd"))' \
		--eval '(asdf:load-asd (truename "source/hackmode-providers/zap/hackmode-provider-zap.asd"))' \
		--eval '(asdf:load-system :hackmode-provider-zap)' \
		--eval '(asdf:load-system :hackmode-mcp)' \
		--eval "(sb-ext:save-lisp-and-die \"hm-mcp\" :toplevel 'hackmode-mcp:main :executable t :compression t)"
install:
	cp hm /usr/local/bin

clean:
	rm -f hm

clean-mcp:
	rm -f hm-mcp
