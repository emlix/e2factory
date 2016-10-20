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

SUBDIRS = $(shell find . -mindepth 1 -maxdepth 1 -type d)
TOPLEVEL = $(shell pwd)/..

# extensions need a way to locate the source
export TOPLEVEL

include $(TOPLEVEL)/make.vars

CLEAN_FILES = *~

all:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done

install:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done

uninstall:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done

local:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done

install-local:
	for s in $(SUBDIRS) ; do $(MAKE) -C $$s $@; done

doc:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done

install-doc:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done

clean:
	for s in $(SUBDIRS); do $(MAKE) -C $$s $@; done
	rm -f $(CLEAN_FILES)

.PHONY: all install local install-local doc install-doc clean

