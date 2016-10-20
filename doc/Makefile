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

SUBDIRS    = ldoc developer man
TOPLEVEL = ..

include $(TOPLEVEL)/make.vars

CLEAN_FILES = documentation.tar.gz

.PHONY: all install install-local clean local localdist uninstall \
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

doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	$(MAKE) documentation.tar.gz

documentation.tar.gz: developer/e2factory.tar.gz \
					man/man.tar.gz
	rm -fr documentation
	mkdir -p documentation/developer
	tar -C documentation/developer -xzf developer/e2factory.tar.gz
	tar -C documentation -xzf man/man.tar.gz
	cp $(TOPLEVEL)/Changelog documentation
	tar -czf documentation.tar.gz documentation

install-doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

clean:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	rm -fr documentation
	rm -f $(CLEAN_FILES)
