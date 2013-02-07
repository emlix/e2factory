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

VPATH = .:$(TOPLEVEL)/generic:$(TOPLEVEL)

SCRIPTS =
GLOBALLUATOOLS = e2-create-project e2-fetch-project e2-install-e2
GLOBALSHTOOLS = e2-locate-project-root e2-su
GLOBALTOOLS = $(GLOBALLUATOOLS) $(GLOBALSHTOOLS)
CLEAN_FILES = e2 e2.conf
LUA_LIBS = strict.lua plugin.lua e2lib.lua
LUA_LIBS += e2option.lua hash.lua tools.lua transport.lua cache.lua url.lua
LUA_LIBS += generic_git.lua luafile.lua err.lua lock.lua
LUA_LIBS += buildconfig.lua

.PHONY: all install uninstall clean

all: e2 $(SCRIPTS) \
	$(GLOBALSHTOOLS:=.sh) e2.conf sha1.so e2-su-2.2 \
	luafile_ll.so e2util.so

install-dirs:
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(LIBDIR)
	install -d $(DESTDIR)$(LIBEXECDIR)
	install -d $(DESTDIR)$(INCDIR)
	install -d $(DESTDIR)$(MANDIR)
	install -d $(DESTDIR)$(TOOLDIR)
	install -d $(DESTDIR)$(SYSCONFDIR)
	install -d -m 2775 -g $(E2_GROUP) $(DESTDIR)$(LOCALSTATEDIR)

install-lua: $(LUA_LIBS)
	install -m 644 $^ $(DESTDIR)$(LIBDIR)

install: all install-dirs install-lua
	set -e; for i in $(GLOBALLUATOOLS) ; do \
		install -m 755 $$i.lua $(DESTDIR)$(TOOLDIR)/$$i ; \
		ln -sf e2 $(DESTDIR)$(BINDIR)/$$i ; \
	done
	set -e; for i in $(GLOBALSHTOOLS) ; do \
		install -m 755 $$i.sh $(DESTDIR)$(BINDIR)/$$i ; \
	done
	install -m 755 e2 $(DESTDIR)$(BINDIR)/
	if [ ! -f "$(DESTDIR)$(SYSCONFDIR)/e2.conf" ] ; then \
		install -m 644 e2.conf $(DESTDIR)$(SYSCONFDIR)/e2.conf ; \
	fi
	install -m 644 e2.conf $(DESTDIR)$(SYSCONFDIR)/e2.conf.sample
	install -m 755 sha1.so $(DESTDIR)$(LIBDIR)
	install -m 755 luafile_ll.so $(DESTDIR)$(LIBDIR)
	install -m 755 e2util.so $(DESTDIR)$(LIBDIR)
	$(SUDO) install -m 4754 -o root -g $(E2_GROUP) e2-su-2.2 \
		$(DESTDIR)$(BINDIR)/

uninstall:
	set -e; for i in $(GLOBALLUATOOLS) ; do \
		rm -f $(DESTDIR)$(TOOLDIR)/$$i ; \
		rm -f $(DESTDIR)$(BINDIR)/$$i ; \
	done
	set -e; for i in $(GLOBALSHTOOLS) ; do \
		rm -f $(DESTDIR)$(BINDIR)/$$i ; \
	done
	rm -f $(DESTDIR)$(BINDIR)/e2-su-2.2
	rm -f $(DESTDIR)$(LIBDIR)/luafile_ll.so
	rm -f $(DESTDIR)$(LIBDIR)/e2util.so
	rm -f $(DESTDIR)$(BINDIR)/e2

doc:
	set -e; for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	set -e; for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

clean:
	rm -f $(CLEAN_FILES)

%.lua: %.lua.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

%.sh: %.sh.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

e2: e2.lua
	echo "#!$(LIBEXECDIR)/e2-lua-$(LUA_VERSION)" >$@
	cat $< >>$@

e2.conf: e2.conf.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

sha1.so: sha1.o lsha1.o

luafile_ll.so: luafile_ll.o

e2util.so: e2util.o

%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)

CLEAN_FILES += *.o
%.o: %.c
	$(CC) $(CFLAGS) $(BUILD_LUA_CPPFLAGS) -fPIC -c -o $@ $<

CLEAN_FILES += e2-su-2.2
e2-su-2.2: e2-su-2.2.c
	$(CC) $(CFLAGS) $(CPPFLAGS) $(E2_SU_CFLAGS) $(LDFLAGS) $< -o $@

