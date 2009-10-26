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

### Makefile for "generic" e2 subdirectory


TOPLEVEL = ..

include $(TOPLEVEL)/make.vars

CLEAN_FILES = *~ *.lc *.so lua-version-map.lua e2-su-2.2


.PHONY: all install uninstall local install-local clean

all: e2generic_global.lc luafile_ll_global.so e2util_global.so e2-su-2.2 \
	lock.lc

install: all
	install -m 644 e2generic_global.lc $(DESTDIR)$(LIBDIR)
	install -m 644 lock.lc $(DESTDIR)$(LIBDIR)
	install -m 755 luafile_ll_global.so $(DESTDIR)$(LIBDIR)
	install -m 755 e2util_global.so $(DESTDIR)$(LIBDIR)
	install -m 4754 -o root -g $(E2_GROUP) e2-su-2.2 $(DESTDIR)$(BINDIR)/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/e2-su-2.2
	rm -f $(DESTDIR)$(LIBDIR)/e2generic_global.lc
	rm -f $(DESTDIR)$(LIBDIR)/lock.lc
	rm -f $(DESTDIR)$(LIBDIR)/luafile_ll_global.so
	rm -f $(DESTDIR)$(LIBDIR)/e2util_global.so

local: e2generic_local.lc luafile_ll_local.so e2util_local.so lock.lc

install-local: local
	mkdir -p $(LOCALLIBDIR) $(LOCALMAKDIR)
	install -m 644 e2generic_local.lc $(LOCALLIBDIR)
	install -m 644 lock.lc $(LOCALLIBDIR)
	install -m 755 luafile_ll_local.so $(LOCALLIBDIR)
	install -m 755 e2util_local.so $(LOCALLIBDIR)
	install -m 644 e2-su-2.2.c $(LOCALMAKDIR)

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

e2generic_global.lc: strict.lua collection.lua e2lib_global_prefix.lua \
		e2lib.lua e2option.lua sha1.lua \
		transport.lua cache.lua url.lua scm.git.lua \
		luafile.lua lua-version-map.lua \
		error.lua
	$(BUILD_LUAC) -o $@ $^

e2generic_local.lc: strict.lua collection.lua e2lib_local_prefix.lua \
		e2lib.lua e2option.lua sha1.lua \
		transport.lua cache.lua url.lua scm.git.lua \
		luafile.lua lua-version-map.lua
	$(LUAC) -o $@ $^

%: %.in
	$(TOPLEVEL)/scripts/genscript.sh $< $@

%.lc: %.lua
	$(BUILD_LUAC) -o $@ $<

e2-su-2.2: e2-su-2.2.c
	$(CC) $(CFLAGS) $(E2_SU_CFLAGS) $(LDFLAGS) $< -o $@

luafile_ll_global.so: luafile_ll.c
	$(CC) $(CFLAGS) $(BUILD_LUA_CPPFLAGS) $(LDFLAGS) -shared -fPIC $< -o $@

e2util_global.so: e2util.c
	$(CC) $(CFLAGS) $(BUILD_LUA_CPPFLAGS) $(LDFLAGS) -shared -fPIC $< -o $@

luafile_ll_local.so: luafile_ll.c
	$(CC) -DLOCAL $(CFLAGS) $(LUA_CPPFLAGS) $(LDFLAGS) -shared -fPIC $< -o $@

e2util_local.so: e2util.c
	$(CC) -DLOCAL $(CFLAGS) $(LUA_CPPFLAGS) $(LDFLAGS) -shared -fPIC $< -o $@
