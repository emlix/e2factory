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

TOPLEVEL = ..

include $(TOPLEVEL)/make.vars

#VPATH = .:$(TOPLEVEL)/generic:$(TOPLEVEL)

SCRIPTS =
GLOBALLUATOOLS = e2-create-project e2-fetch-project e2-install-e2
GLOBALSHTOOLS = e2-locate-project-root e2-su
GLOBALTOOLS = $(GLOBALLUATOOLS) $(GLOBALSHTOOLS)
CLEAN_FILES = e2 e2.conf

.PHONY: all install uninstall clean

all: e2 $(SCRIPTS) \
	$(GLOBALSHTOOLS:=.sh) e2.conf e2-su-2.2 \

install-dirs:
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)$(LIBEXECDIR)
	install -d $(DESTDIR)$(INCDIR)
	install -d $(DESTDIR)$(MANDIR)
	install -d $(DESTDIR)$(TOOLDIR)
	install -d $(DESTDIR)$(SYSCONFDIR)
	install -d -m 2775 -g $(E2_GROUP) $(DESTDIR)$(LOCALSTATEDIR)


install: all install-dirs
	for i in $(GLOBALLUATOOLS) ; do \
		install -m 755 $$i.lua $(DESTDIR)$(TOOLDIR)/$$i ; \
		ln -sf e2 $(DESTDIR)$(BINDIR)/$$i ; \
	done
	for i in $(GLOBALSHTOOLS) ; do \
		install -m 755 $$i.sh $(DESTDIR)$(BINDIR)/$$i ; \
	done
	install -m 755 e2 $(DESTDIR)$(BINDIR)/
	if [ ! -f "$(DESTDIR)$(SYSCONFDIR)/e2.conf" ] ; then \
		install -m 644 e2.conf $(DESTDIR)$(SYSCONFDIR)/e2.conf ; \
	fi
	install -m 644 e2.conf $(DESTDIR)$(SYSCONFDIR)/e2.conf.sample
	$(SUDO) install -m 4754 -o root -g $(E2_GROUP) e2-su-2.2 \
		$(DESTDIR)$(BINDIR)/

uninstall:
	for i in $(GLOBALLUATOOLS) ; do \
		rm -f $(DESTDIR)$(TOOLDIR)/$$i ; \
		rm -f $(DESTDIR)$(BINDIR)/$$i ; \
	done
	for i in $(GLOBALSHTOOLS) ; do \
		rm -f $(DESTDIR)$(BINDIR)/$$i ; \
	done
	rm -f $(DESTDIR)$(BINDIR)/e2-su-2.2
	rm -f $(DESTDIR)$(BINDIR)/e2

local:

install-local:  e2-su-2.2.c
	install -d $(LOCALMAKDIR)
	install -m 644  e2-su-2.2.c  $(LOCALMAKDIR)

uninstall-local:
	rm -f $(LOCALMAKDIR)/e2-su-2.2.c
	rmdir -p $(LOCALMAKDIR) || true

doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

clean:
	rm -f $(CLEAN_FILES)

%.lua: %.lua.in
	$(GENSCRIPT) $< $@

%.sh: %.sh.in
	$(GENSCRIPT) $< $@

e2: e2.lua
	echo "#!$(LIBEXECDIR)/e2-lua-$(LUA_VERSION)" >$@
	cat $< >>$@

e2.conf: e2.conf.in
	$(GENSCRIPT) $< $@

%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)

CLEAN_FILES += *.o
%.o: %.c
	$(CC) $(CFLAGS) $(BUILD_LUA_CPPFLAGS) -fPIC -c -o $@ $<

CLEAN_FILES += e2-su-2.2
e2-su-2.2: e2-su-2.2.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(E2_SU_CFLAGS) $(LDFLAGS) $< -o $@

