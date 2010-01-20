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

CLEAN_FILES = *~ *.so linux32 *.lc *.o
CFLAGS += -I. -I$(DESTDIR)$(INCDIR) -I$(DESTDIR)$(INCDIR)/lua-$(LUA_VERSION) \
	-I../lua/lua-$(LUA_VERSION)/src -fPIC
LDFLAGS += -L. -L../lua/lua-$(LUA_VERSION)/src -Wl,-R$(LIBDIR) 
LOCALLUATOOLS = \
	build dlist dsort fetch-sources new-source ls-project \
	playground build-numbers cf
LOCALSHTOOLS =
LOCALTOOLS = $(LOCALSHTOOLS) $(LOCALLUATOOLS)

SYMLINKS_2_1 = lookup-server use-source prepare-cargo sync-results cleanup \
	git-to-tar required-files buildid

.PHONY: all install uninstall install install-local doc install-doc


all: linux32 e2local.lc $(LOCALLUATOOLS:=.lc)

install:
	# install symlinks for e2-2.1 compatibility
	for i in $(SYMLINKS_2_1); do \
		ln -sf e2 $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done
	for i in $(LOCALTOOLS); do \
		ln -sf e2 $(DESTDIR)$(BINDIR)/e2-$$i ; \
	done

install-local: all
	test -n "$(PROJECTDIR)"
	mkdir -p $(LOCALBINDIR) $(LOCALMAKDIR) $(LOCALLIBDIR)
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

e2local.lc: $(TOPLEVEL)/generic/strict.lua \
		result.lua \
		loader.lua \
		environment.lua \
		$(TOPLEVEL)/generic/plugin.lua \
		$(TOPLEVEL)/generic/scm.git.lua \
		$(TOPLEVEL)/generic/tools.lua \
		$(TOPLEVEL)/generic/transport.lua \
		$(TOPLEVEL)/generic/cache.lua \
		$(TOPLEVEL)/generic/error.lua \
		$(TOPLEVEL)/generic/url.lua \
		$(TOPLEVEL)/generic/collection.lua \
		$(TOPLEVEL)/generic/e2lib.lua \
		e2tool.lua e2scm.lua git.lua svn.lua cvs.lua files.lua \
		$(TOPLEVEL)/generic/e2option.lua \
		$(TOPLEVEL)/generic/hash.lua \
		$(TOPLEVEL)/generic/lock.lua \
		e2build.lua $(TOPLEVEL)/generic/luafile.lua \
		policy.lua
	$(LUAC) -o $@ $^

linux32: linux32.c
