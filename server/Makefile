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

#### Makefile for build-number and log server


TOPLEVEL = ..

include $(TOPLEVEL)/make.vars

SERVER_VERSION = 0.1
CFLAGS = -g -DVERSION=\"$(SERVER_VERSION)\" -DSHAREDIR=\"$(SHAREDIR)\" \
	-DLIBEXECDIR=\"$(LIBEXECDIR)\" -DLUA_VERSION=\"$(LUA_VERSION)\"

.PHONY: all clean install

all: web/store-run-log.lua web/retrieve-build-numbers.lua

clean:
	rm -f *~ *.o web/*.lua

web/%.lua: web/%.lua.in
	sed -e 's,@LOGDIR@,$(SERVER_LOGDIR),g' \
	  <$< >$@

install: all
	mkdir -p $(DESTDIR)$(SHAREDIR)/e2-server/web
	install -m644 web/*.lua $(DESTDIR)$(SHAREDIR)/e2-server/web
