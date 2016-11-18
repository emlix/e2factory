# Copyright (C) 2007-2016 emlix GmbH, see file AUTHORS
#
# This file is part of e2factory, the emlix embedded build system.
# For more information see http://www.e2factory.org
#
# e2factory is a registered trademark of emlix GmbH.
#
# e2factory is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.

SUBDIRS    = lua generic global local plugins doc templates extensions
TOPLEVEL = .

include $(TOPLEVEL)/make.vars

CLEAN_FILES = *~ buildconfig.lua


.PHONY: all install install-local clean local localdist uninstall \
	doc buildconfig.lua tags

help:
	@cat INSTALL

.SILENT: buildconfig.lua
buildconfig.lua: Makefile make.vars
	echo 'writing buildconfig.lua'
	echo 'local buildconfig = {}' > $@
	echo 'local strict = require("strict")' >>$@
	echo 'buildconfig.PREFIX="$(PREFIX)"' >>$@
	echo 'buildconfig.BINDIR="$(BINDIR)"' >>$@
	echo 'buildconfig.LIBDIR="$(LIBDIR)"' >>$@
	echo 'buildconfig.TOOLDIR="$(TOOLDIR)"' >>$@
	echo 'buildconfig.SYSCONFDIR="$(SYSCONFDIR)"' >>$@
	echo 'buildconfig.E2="$(E2)"' >>$@
	echo 'buildconfig.LUA="$(LUA)"' >>$@
	echo 'buildconfig.MAKE="$(MAKE)"' >> $@
	echo 'buildconfig.MAJOR="$(MAJOR)"' >>$@
	echo 'buildconfig.MINOR="$(MINOR)"' >>$@
	echo 'buildconfig.PATCHLEVEL="$(PATCHLEVEL)"' >>$@
	echo 'buildconfig.EXTRAVERSION="$(EXTRAVERSION)"' >>$@
	echo 'buildconfig.VERSION="$(VERSION)"' >>$@
	echo 'buildconfig.VERSIONSTRING="$(VERSIONSTRING)"' >>$@
	echo 'buildconfig.GLOBAL_INTERFACE_VERSION={' >>$@
	for x in $(GLOBAL_INTERFACE_VERSION) ; do \
		echo " \"$$x\"," ; done >>$@
	echo '}' >>$@
	echo 'buildconfig.SYNTAX={' >>$@
	for x in $(SYNTAX) ; do echo " \"$$x\"," ; done >>$@
	echo '}' >>$@
	echo 'return strict.lock(buildconfig)' >>$@


all: buildconfig.lua
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	@echo "Build successful!"

install: all
	install -d $(DESTDIR)$(LIBDIR)
	install -m 644 buildconfig.lua $(DESTDIR)$(LIBDIR)
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	@echo "Installation successful!"

uninstall:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	rm -f $(DESTDIR)$(LIBDIR)/buildconfig.lua
	rmdir -p $(DESTDIR)$(LIBDIR) || true
	rmdir -p $(DESTDIR)$(DOCDIR) || true

local: buildconfig.lua
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-local: local
	$(BINDIR)/e2-locate-project-root
	@echo removing old installation...
	rm -rf $(LOCALBINDIR)
	rm -rf $(LOCALLIBDIR)
	rm -rf $(LOCALMAKDIR)
	rm -rf $(LOCALDOCDIR)
	@echo removing old plugins...
	rm -rf $(LOCALPLUGINDIR)
	install -d $(LOCALLIBDIR)
	install -m 644 buildconfig.lua $(LOCALLIBDIR)
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	install -d -m 755 $(DESTDIR)$(DOCDIR)
	install -m 644 Changelog $(DESTDIR)$(DOCDIR)/
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

clean:
	rm -f $(CLEAN_FILES)
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

showtag:
	@echo $(TAG)
