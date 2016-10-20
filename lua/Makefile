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

.PHONY: clean all install

LUA_HEADER = lua.h lauxlib.h lualib.h luaconf.h

.PHONY: lua-5.1.3
lua-5.1.3:
	$(MAKE) -C lua-5.1.3/src all MYCFLAGS="\
		-DLUA_USE_POSIX -DLUA_USE_DLOPEN \
		-DLUA_PATH_DEFAULT='\"$(LIBDIR)/?.lua\"' \
		-DLUA_CPATH_DEFAULT='\"$(LIBDIR)/?.so\"'" \
		MYLIBS="-Wl,-E -ldl"

all: lua-5.1.3

install: all
	install -d $(DESTDIR)$(LIBEXECDIR)
	install -m755 lua-5.1.3/src/lua $(DESTDIR)$(LIBEXECDIR)/e2-lua-5.1.3
	install -m755 lua-5.1.3/src/luac $(DESTDIR)$(LIBEXECDIR)/e2-luac-5.1.3
	install -d $(DESTDIR)$(INCDIR)/lua-5.1.3
	install -m644 lua-5.1.3/src/lua.h $(DESTDIR)$(INCDIR)/lua-5.1.3
	install -m644 lua-5.1.3/src/lauxlib.h $(DESTDIR)$(INCDIR)/lua-5.1.3
	install -m644 lua-5.1.3/src/lualib.h $(DESTDIR)$(INCDIR)/lua-5.1.3
	install -m644 lua-5.1.3/src/luaconf.h $(DESTDIR)$(INCDIR)/lua-5.1.3

uninstall:
	rm -f $(DESTDIR)$(LIBEXECDIR)/e2-lua-5.1.3
	rm -f $(DESTDIR)$(LIBEXECDIR)/e2-luac-5.1.3
	rmdir -p $(DESTDIR)$(LIBEXECDIR)/lua-5.1.3 || true
	for x in $(LUA_HEADER) ; do \
		rm -f $(DESTDIR)$(INCDIR)/lua-5.1.3/$$x ; \
	done
	rmdir -p $(DESTDIR)$(INCDIR)/lua-5.1.3 || true

local:

install-local:

doc:

install-doc:

clean:
	$(MAKE) -C lua-5.1.3/src clean
