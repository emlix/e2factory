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

VPATH = .:$(TOPLEVEL)/generic

CLEAN_FILES = *~ *.so linux32 *.lc *.o
CFLAGS += -I. -I$(DESTDIR)$(INCDIR) -I$(DESTDIR)$(INCDIR)/lua-$(LUA_VERSION) \
	-I../lua/lua-$(LUA_VERSION)/src -fPIC
LDFLAGS += -L. -L../lua/lua-$(LUA_VERSION)/src -Wl,-R$(LIBDIR) 
LOCALLUATOOLS = \
	build dlist dsort fetch-sources new-source ls-project \
	playground build-numbers cf
LOCALSHTOOLS =
LUA_LIBS = e2option.lua luafile.lua generic_git.lua err.lua
LUA_LIBS += e2tool.lua scm.lua git.lua svn.lua cvs.lua files.lua
LOCALTOOLS = $(LOCALSHTOOLS) $(LOCALLUATOOLS)

SYMLINKS_2_1 = lookup-server use-source prepare-cargo sync-results cleanup \
	git-to-tar required-files buildid

.PHONY: all install uninstall install install-local doc install-doc


all: linux32 e2local.lc $(LOCALLUATOOLS:=.lc) sha1.so luafile_ll.so e2util.so

install:
	# install symlinks for e2-2.1 compatibility
	for i in $(SYMLINKS_2_1); do \
		ln -sf e2 $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done
	for i in $(LOCALTOOLS); do \
		ln -sf e2 $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done

install-local-dirs:
	mkdir -p $(LOCALBINDIR) $(LOCALMAKDIR) $(LOCALLIBDIR)

install-local-lua: $(LUA_LIBS)
	install -m 644 $^ $(LOCALLIBDIR)

install-local: all install-local-dirs install-local-lua install-local-sourcefiles
	test -n "$(PROJECTDIR)"
	install -m 755 -d $(LOCALPLUGINDIR)
	install -m644 e2local.lc $(LOCALLIBDIR)/
	for i in $(LOCALLUATOOLS); do \
		install -m 755 $$i.lc $(LOCALBINDIR)/e2-$$i; \
	done
	for i in $(LOCALSHTOOLS); do \
		install -m 755 $$i $(LOCALBINDIR)/e2-$$i; \
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
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

uninstall:
	for i in $(SYMLINKS_2_1); do \
		rm -f $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done
	for i in $(LOCALTOOLS); do \
		rm -f $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done

clean:
	rm -f $(CLEAN_FILES)

%: %.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

%.lc: %.lua
	$(LUAC) -o $@ $<

e2local.lc: strict.lua \
		loader.lua \
		environment.lua \
		plugin.lua \
		tools.lua \
		transport.lua \
		cache.lua \
		url.lua \
		collection.lua \
		e2lib.lua \
		hash.lua \
		lock.lua \
		e2build.lua \
		policy.lua
	$(LUAC) -o $@ $^

linux32: linux32.c

sha1.so: sha1.o lsha1.o

luafile_ll.so: luafile_ll.o

e2util.so: e2util.o

%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)
