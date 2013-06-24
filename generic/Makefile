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

LUA_LIBS = strict.lua plugin.lua e2lib.lua
LUA_LIBS += e2option.lua hash.lua tools.lua transport.lua cache.lua url.lua
LUA_LIBS += generic_git.lua luafile.lua err.lua lock.lua

CLEAN_FILES = *~ *.o *.so


.PHONY: all install uninstall local install-local clean

all: sha1.so luafile_ll.so e2util.so

sha1.so: sha1.o lsha1.o

luafile_ll.so: luafile_ll.o

e2util.so: e2util.o

install: all
	install -d $(DESTDIR)$(LIBDIR)
	install -m 644 $(LUA_LIBS) $(DESTDIR)$(LIBDIR)
	install -m 644 sha1.so $(DESTDIR)$(LIBDIR)
	install -m 644 luafile_ll.so $(DESTDIR)$(LIBDIR)
	install -m 644 e2util.so $(DESTDIR)$(LIBDIR)

uninstall:
	rm -f  $(DESTDIR)$(LIBDIR)/sha1.so
	rm -f  $(DESTDIR)$(LIBDIR)/luafile_ll.so
	rm -f  $(DESTDIR)$(LIBDIR)/e2util.so
	set -e; for f in $(LUA_LIBS); do \
		rm -f "$(DESTDIR)$(LIBDIR)/$$f"; \
	done
	rmdir -p $(DESTDIR)$(LIBDIR) || true

local: sha1.so luafile_ll.so e2util.so

install-local: local
	install -d $(LOCALLIBDIR)
	install -m 644 sha1.so $(LOCALLIBDIR)
	install -m 644 luafile_ll.so $(LOCALLIBDIR)
	install -m 644 e2util.so $(LOCALLIBDIR)

uninstall-local:
	rm -f  $(LOCALLIBDIR)/sha1.so
	rm -f  $(LOCALLIBDIR)/luafile_ll.so
	rm -f $(LOCALLIBDIR)/e2util.so
	rmdir -p $(LOCALLIBDIR) || true

doc:

install-doc:

clean:
	rm -f $(CLEAN_FILES)

%.o: %.c
	$(CC) $(CFLAGS) $(BUILD_LUA_CPPFLAGS) $(LDFLAGS) -fPIC -o $@ -c $<

%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)
