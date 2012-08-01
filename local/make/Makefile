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

SUBDIRS =
TOPLEVEL = ../..

include $(TOPLEVEL)/make.vars

CLEAN_FILES = *~

.PHONY: all install-local clean

all:

install-local:
	install -m 755 -d $(LOCALMAKDIR)
	install -m644 makefile.template $(LOCALMAKDIR)/makefile
	install -m644 makefile.res.template $(LOCALMAKDIR)/makefile.res
	install -m644 makefile.collect_project $(LOCALMAKDIR)/Makefile
	install -m755 detect_tool $(LOCALMAKDIR)/
	install -m644 buildall.sh build.sh $(LOCALMAKDIR)/

clean:
	rm -f $(CLEAN_FILES)
