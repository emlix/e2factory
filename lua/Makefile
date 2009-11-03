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

.PHONY: clean all install

#
# if they change the way Lua is built, we have a problem.
#

LUA_HEADER = lua.h lauxlib.h lualib.h luaconf.h

lua-5.1.3:
	tar -xzf $(LUA_SOURCE_PATH)/lua-5.1.3.tar.gz -C $(LUA_UNPACK_PATH); \
	$(MAKE) -C $(LUA_UNPACK_PATH)/lua-5.1.3/src all \
	    MYCFLAGS="-DLUA_USE_POSIX -DLUA_USE_DLOPEN" MYLIBS="-Wl,-E -ldl"; \

all: lua-5.1.3

install: all
	mkdir -p $(DESTDIR)$(INCDIR)/lua-5.1.3; \
	install -m755 $(LUA_UNPACK_PATH)/lua-5.1.3/src/lua $(DESTDIR)$(LIBEXECDIR)/e2-lua-5.1.3; \
	install -m755 $(LUA_UNPACK_PATH)/lua-5.1.3/src/luac $(DESTDIR)$(LIBEXECDIR)/e2-luac-5.1.3; \
	install -m644 $(LUA_UNPACK_PATH)/lua-5.1.3/src/lua.h $(DESTDIR)$(INCDIR)/lua-5.1.3; \
	install -m644 $(LUA_UNPACK_PATH)/lua-5.1.3/src/lauxlib.h $(DESTDIR)$(INCDIR)/lua-5.1.3; \
	install -m644 $(LUA_UNPACK_PATH)/lua-5.1.3/src/lualib.h $(DESTDIR)$(INCDIR)/lua-5.1.3; \
	install -m644 $(LUA_UNPACK_PATH)/lua-5.1.3/src/luaconf.h $(DESTDIR)$(INCDIR)/lua-5.1.3; \

uninstall: 
	rm -f $(DESTDIR)$(LIBEXECDIR)/e2-lua-5.1.3; \
	rm -f $(DESTDIR)$(LIBEXECDIR)/e2-luac-5.1.3; \
	rm -fr $(DESTDIR)$(LIBEXECDIR)/lua-5.1.3; \
	for x in $(LUA_HEADER) ; do \
		rm -f $(DESTDIR)$(INCDIR)/lua-5.1.3/$$x ; \
	done
	rmdir -p $(DESTDIR)$(INCDIR)/lua-5.1.3 || :

doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

clean:
	rm -fr $(LUA_ALL_VERSIONS:%=lua-%)
