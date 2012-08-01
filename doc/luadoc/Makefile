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

SUBDIRS    =
TOPLEVEL   = ../..

DIR        = $(shell pwd)

include $(TOPLEVEL)/make.vars

CLEAN_FILES = *~ luadoc.tar.gz

.PHONY: all e2commit install install-local clean local localdist uninstall \
	doc

all:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

uninstall:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

local:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-local:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

doc: luadoc.tar.gz
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc: doc
	tar -C $(DOCDIR) -xzf luadoc.tar.gz
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ; \
	done

luadoc.tar.gz: $(TOPLEVEL)/local/*.lua $(TOPLEVEL)/generic/*.lua
	rm -fr luadoc
	mkdir luadoc
	(cd $(TOPLEVEL) ; luadoc -d $(DIR)/luadoc \
		local/*.lua \
		generic/*.lua)
	tar -czf luadoc.tar.gz luadoc

clean:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	rm -f $(CLEAN_FILES)
	rm -fr luadoc

check:
	for s in $(SUBDIRS) do ;\
		$(MAKE) -C $$s $@ ;\
	done

localdist:
	for s in $(SUBDIRS) do ;\
		$(MAKE) -C $$s $@ ;\
	done

