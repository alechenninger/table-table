.DEFAULT_GOAL := all

-include Makefile.local

DART ?= dart
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DESTDIR ?=
INSTALL ?= install

BINARIES := build/table-table build/slack-table build/md-table
SOURCES := $(wildcard lib/*.dart lib/src/*.dart lib/src/clipboard/*.dart)

.PHONY: all install

all: $(BINARIES)

install: all
	$(INSTALL) -d "$(DESTDIR)$(BINDIR)"
	$(INSTALL) -m 755 $(BINARIES) "$(DESTDIR)$(BINDIR)/"

build/table-table: bin/table_table.dart
build/slack-table: bin/slack_table.dart
build/md-table: bin/md_table.dart

$(BINARIES): $(SOURCES) build/.pub-get Makefile
	$(DART) compile exe bin/$(subst -,_,$(@F)).dart -o $@

build/.pub-get: pubspec.yaml pubspec.lock
	mkdir -p build
	$(DART) pub get
	touch $@
