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

LUA_LIBS = strict.lua plugin.lua e2lib.lua console.lua class.lua
LUA_LIBS += e2option.lua hash.lua tools.lua transport.lua cache.lua url.lua
LUA_LIBS += generic_git.lua eio.lua err.lua lock.lua errno.lua trace.lua
LUA_LIBS += assrt.lua
SO_LIBS = lsha1.so leio.so le2lib.so

CLEAN_FILES = *~ *.o *.so


.PHONY: all install uninstall local install-local clean

all: $(SO_LIBS)

lsha1.so: lsha1.o sha1.o

leio.so: leio.o

le2lib.so: le2lib.o

install: all
	install -d $(DESTDIR)$(LIBDIR)
	install -m 644 $(LUA_LIBS) $(DESTDIR)$(LIBDIR)
	install -m 644 $(SO_LIBS) $(DESTDIR)$(LIBDIR)

uninstall:
	for f in $(LUA_LIBS) $(SO_LIBS); do \
		rm -f "$(DESTDIR)$(LIBDIR)/$$f"; \
	done
	rmdir -p $(DESTDIR)$(LIBDIR) || true

local: $(SO_LIBS)

install-local: local
	install -d $(LOCALLIBDIR)
	install -m 644 $(LUA_LIBS) $(LOCALLIBDIR)
	install -m 644 $(SO_LIBS) $(LOCALLIBDIR)

uninstall-local:
	for f in $(LUA_LIBS) $(SO_LIBS); do \
		rm -f "$(LOCALLIBDIR)/$$f"; \
	done
	rmdir -p $(LOCALLIBDIR) || true

doc:

install-doc:

clean:
	rm -f $(CLEAN_FILES)

%.o: %.c
	$(CC) $(CFLAGS) $(BUILD_LUA_CPPFLAGS) $(LDFLAGS) -fPIC -o $@ -c $<

%.so:
	$(CC) -shared -o $@ $^ $(LDFLAGS)
