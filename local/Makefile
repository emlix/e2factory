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

### Makefile for "local" e2 subdirectory


TOPLEVEL = ..

include $(TOPLEVEL)/make.vars

VPATH = .:$(TOPLEVEL)/generic:$(TOPLEVEL)

CLEAN_FILES = *~ *.so linux32 *.o
CFLAGS += -I. -I$(DESTDIR)$(INCDIR) -I$(DESTDIR)$(INCDIR)/lua-$(LUA_VERSION) \
	-I../lua/lua-$(LUA_VERSION)/src -fPIC
LDFLAGS += -L. -L../lua/lua-$(LUA_VERSION)/src -Wl,-R$(LIBDIR)
LOCALLUATOOLS = e2-build e2-dlist e2-dsort e2-fetch-sources \
	e2-new-source e2-ls-project e2-playground \
	e2-build-numbers e2-cf e2-help
LOCALSHTOOLS =
LUA_LIBS = e2option.lua luafile.lua generic_git.lua err.lua
LUA_LIBS += e2tool.lua scm.lua digest.lua
LUA_LIBS += tools.lua transport.lua cache.lua
LUA_LIBS += environment.lua plugin.lua url.lua hash.lua lock.lua
LUA_LIBS += policy.lua strict.lua e2build.lua
LUA_LIBS += e2lib.lua buildconfig.lua
LOCALTOOLS = $(LOCALSHTOOLS) $(LOCALLUATOOLS)
LOCALPLUGINS = cvs.lua files.lua git.lua svn.lua

.PHONY: all install uninstall install install-local doc install-doc


all: linux32 sha1.so luafile_ll.so e2util.so

install:
	set -e; for i in $(LOCALTOOLS); do \
		ln -sf e2 $(DESTDIR)$(BINDIR)/$$i ; \
	done

install-local-dirs:
	mkdir -p $(LOCALBINDIR) $(LOCALMAKDIR) $(LOCALLIBDIR)

install-local-lua: $(LUA_LIBS)
	install -m 644 $^ $(LOCALLIBDIR)

install-local: all install-local-dirs install-local-lua install-local-sourcefiles
	test -n "$(PROJECTDIR)"
	install -m 755 -d $(LOCALPLUGINDIR)
	set -e; for p in $(LOCALPLUGINS) ; do \
		install -m 644 $$p $(LOCALPLUGINDIR)/$$p; \
	done
	set -e; for i in $(LOCALLUATOOLS); do \
		install -m 755 $$i.lua $(LOCALBINDIR)/$$i; \
	done
	set -e; for i in $(LOCALSHTOOLS); do \
		install -m 755 $$i $(LOCALBINDIR)/$$i; \
	done
	install -m755 linux32 $(LOCALBINDIR)/e2-linux32; \
	install -m644 linux32.c $(LOCALMAKDIR)/
	ln -sf $(LIBEXECDIR)/e2-lua-$(LUA_VERSION) $(LOCALBINDIR)/e2-lua
	$(MAKE) -C make install-local
	install -m 755 sha1.so $(LOCALLIBDIR)
	install -m 755 luafile_ll.so $(LOCALLIBDIR)
	install -m 755 e2util.so $(LOCALLIBDIR)

install-local-sourcefiles: e2-su-2.2.c
	install -m 644 $^ $(LOCALMAKDIR)
doc:
	set -e; for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	set -e; for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

uninstall:
	set -e; for i in $(LOCALTOOLS); do \
		rm -f $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done

clean:
	rm -f $(CLEAN_FILES)

%: %.in
	$(GENSCRIPT) $< $@

linux32: linux32.c

sha1.so: sha1.o lsha1.o

luafile_ll.so: luafile_ll.o

e2util.so: e2util.o

%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)
