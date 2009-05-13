#
#  e2factory, the emlix embedded build system
#
#  Copyright (C) 2007-2009 Gordon Hecker <gh@emlix.com>, emlix GmbH
#  Copyright (C) 2007-2009 Oskar Schirmer <os@emlix.com>, emlix GmbH
#  Copyright (C) 2007-2008 Felix Winkelmann, emlix GmbH
#  
#  For more information have a look at http://www.e2factory.org
#
#  e2factory is a registered trademark by emlix GmbH.
#
#  This file is part of e2factory, the emlix embedded build system.
#  
#  e2factory is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#  
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#  
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

SUBDIRS    = lua generic global doc templates extensions
LOCALSUBDIRS    = lua generic global local doc
TOPLEVEL    = .

include $(TOPLEVEL)/make.vars

CLEAN_FILES = *~ E2_COMMIT buildconfig.lua


.PHONY: all e2commit install install-local clean local localdist uninstall \
	doc

help:
	@cat INSTALL

buildconfig.lua: Makefile
	echo 'module ("buildconfig")' > $@
	echo 'PREFIX="$(PREFIX)"' >>$@
	echo 'BINDIR="$(BINDIR)"' >>$@
	echo 'LIBDIR="$(LIBDIR)"' >>$@
	echo 'TOOLDIR="$(TOOLDIR)"' >>$@
	echo 'E2="$(E2)"' >>$@
	echo 'LUA="$(LUA)"' >>$@
	echo 'E2_VERSION="$(E2_VERSION)"' >>$@
	echo 'E2_COMMIT="$(E2_COMMIT)"' >>$@
	echo 'E2_SYNTAX="$(E2_SYNTAX)"' >>$@

all: e2commit buildconfig.lua
	$(MAKE) -C lua
	$(MAKE) -C generic
	$(MAKE) -C global
	$(MAKE) -C doc/man
	$(MAKE) -C templates all
	$(MAKE) -C extensions all

# this target creates a file E2_COMMIT, holding the current E2_COMMIT 
# string, and cleans the tree in case E2_COMMIT changed since the last 
# time. That makes sure that the builtin version string is always correct.

e2commit:
	@if [ "$(E2_COMMIT)" != "$(shell cat E2_COMMIT)" ] ; then \
		echo "E2_COMMIT changed. making clean first." ; \
		$(MAKE) clean ; \
		echo "$(E2_COMMIT)" > E2_COMMIT ; \
	fi

install: all
	mkdir -p $(DESTDIR)$(BINDIR)
	mkdir -p $(DESTDIR)$(LIBDIR)
	mkdir -p $(DESTDIR)$(LIBEXECDIR)
	mkdir -p $(DESTDIR)$(INCDIR)
	mkdir -p $(DESTDIR)$(MANDIR)
	mkdir -p $(DESTDIR)$(TOOLDIR)
	install -m 644 buildconfig.lua $(DESTDIR)$(LIBDIR)
	$(MAKE) -C lua install
	$(MAKE) -C generic install
	$(MAKE) -C global install
	$(MAKE) -C local install
	$(MAKE) -C doc/man install
	$(MAKE) -C templates install
	$(MAKE) -C extensions install

uninstall:
	$(MAKE) -C lua uninstall
	$(MAKE) -C generic uninstall
	$(MAKE) -C global uninstall
	$(MAKE) -C doc/man uninstall
	$(MAKE) -C templates uninstall
	$(MAKE) -C local uninstall

local: e2commit buildconfig.lua
	$(MAKE) -C generic local
	$(MAKE) -C local
	$(MAKE) -C templates local
	$(MAKE) -C extensions local

install-local:
	scripts/e2-locate-project-root
	$(MAKE) -C generic install-local
	$(MAKE) -C local install-local
	$(MAKE) -C templates install-local
	$(MAKE) -C extensions install-local
	install -m 644 buildconfig.lua $(LOCALLIBDIR)

doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	install -d -m 755 $(DOCDIR)
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	install -m 644 Changelog $(DOCDIR)/

clean: 
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	for s in $(LOCALSUBDIRS) ; do \
		$(MAKE) -C $$s $@ ; \
	done
	rm -f $(CLEAN_FILES)
	if [ -d $(PWD)/test/e2 ]; then \
	  sudo $(MAKE) -C test clean; \
	fi

check:
	@echo building e2...
	make clean >/dev/null 2>&1
	make PREFIX=$(PWD)/test/e2 >/dev/null 2>&1
	sudo make PREFIX=$(PWD)/test/e2 install >/dev/null 2>&1
	make -C test check

localdist: all
	if test -z "$(DISTNAME)"; then \
	  echo; \
	  echo "please re-invoke with DISTNAME set to the tag you want to package"; \
	  echo; \
	  exit 1; \
	fi
	rm -fr dist
	$(MAKE) -C local PROJECTDIR=$$PWD/dist install-local
	$(MAKE) -C generic PROJECTDIR=$$PWD/dist install-local
	tar -czvf e2-$(DISTNAME)-$(ARCH)-local.tar.gz -C dist .e2
	rm -fr dist

dist:
	git archive --format=tar --prefix=$(PACKAGE)/ $(PACKAGE) \
							>$(PACKAGE).tar
	gzip <$(PACKAGE).tar >$(PACKAGE).tar.gz
