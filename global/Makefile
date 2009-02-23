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

TOPLEVEL = ..

include $(TOPLEVEL)/make.vars

SCRIPTS =
GLOBALLUATOOLS = e2-create-project e2-fetch-project e2-install-e2 e2-root
GLOBALSHTOOLS = e2-locate-project-root e2ssh
GLOBALTOOLS = $(GLOBALLUATOOLS) $(GLOBALSHTOOLS)
CLEAN_FILES = *~ $(GLOBALTOOLS) *.lc e2 $(SCRIPTS) *.lua e2-su *.sh e2.conf


.PHONY: all install uninstall clean

all: e2 e2-root e2global.lc $(SCRIPTS) e2-su $(GLOBALLUATOOLS:=.lc) \
	$(GLOBALSHTOOLS:=.sh) e2.conf

install: all
	for i in $(GLOBALLUATOOLS) ; do \
		install -m 755 $$i.lc $(DESTDIR)$(TOOLDIR)/$$i ; \
		ln -sf e2 $(DESTDIR)$(BINDIR)/$$i ; \
	done
	for i in $(GLOBALSHTOOLS) ; do \
		install -m 755 $$i.sh $(DESTDIR)$(BINDIR)/$$i ; \
	done
	install -m 755 e2-root $(DESTDIR)$(TOOLDIR)/
	install -m 4754 -o root -g $(E2_GROUP) e2-su $(DESTDIR)$(BINDIR)/
	install -m 755 e2 $(DESTDIR)$(BINDIR)/
	install -m 644 e2global.lc $(DESTDIR)$(LIBDIR)/
	install -d $(SYSCONFDIR)
	if [ ! -f "$(SYSCONFDIR)/e2.conf" ] ; then \
		install -m 644 e2.conf $(SYSCONFDIR)/e2.conf ; \
	fi
	install -m 644 e2.conf $(SYSCONFDIR)/e2.conf.sample
	install -d -m 2775 -g $(E2_GROUP) $(LOCALSTATEDIR)

uninstall:
	for i in $(GLOBALLUATOOLS) ; do \
		rm -f $(DESTDIR)$(TOOLDIR)/$$i ; \
		rm -f $(DESTDIR)$(BINDIR)/$$i ; \
	done
	for i in $(GLOBALSHTOOLS) ; do \
		rm -f $(DESTDIR)$(BINDIR)/$$i ; \
	done
	rm -f $(DESTDIR)$(TOOLDIR)/e2-root
	rm -f $(DESTDIR)$(BINDIR)/e2-su
	rm -f $(DESTDIR)$(BINDIR)/e2
	rm -f $(DESTDIR)$(LIBDIR)/e2global.lc

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

e2global.lc: config.lua e2global.lua
	$(BUILD_LUAC) -o $@ $^

%.lua: %.lua.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

%.lc: %.lua
	$(BUILD_LUAC) -o $@ $<

e2-su: e2-su.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $< -o $@

%.sh: %.sh.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

e2: e2.lc
	echo "#!$(LIBEXECDIR)/e2-lua-$(LUA_VERSION)" >$@
	cat $< >>$@

e2-root: e2-root.lc
	echo "#!$(LIBEXECDIR)/e2-lua-$(LUA_VERSION)" >$@
	cat $< >>$@

e2.conf: e2.conf.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

