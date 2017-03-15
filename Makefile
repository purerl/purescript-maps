.PHONY: ps erl all test

all: ps erl

ps:
	psc-package sources | xargs pserlc 'test/**/*.purs' 'src/**/*.purs'

test: ps erl
	erl -pa ebin -noshell -eval '(test_main@ps:main@c())()' -eval 'init:stop()'

erl:
	mkdir -p ebin
	erlc -o ebin/ output/*/*.erl
