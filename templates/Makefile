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

.PHONY: all clean install uninstall

all:

clean:

install: all
	install -m 755 -d $(DESTDIR)$(SYSCONFDIR)/templates/proj
	install -m 644 proj/config $(DESTDIR)$(SYSCONFDIR)/templates/proj/config
	install -m 644 proj/chroot $(DESTDIR)$(SYSCONFDIR)/templates/proj/chroot
	install -m 644 proj/licences $(DESTDIR)$(SYSCONFDIR)/templates/proj/licences
	install -m 644 proj/env    $(DESTDIR)$(SYSCONFDIR)/templates/proj/env
	install -m 644 gitignore   $(DESTDIR)$(SYSCONFDIR)/templates/gitignore

install-local: all
	install -m 755 -d $(LOCALLIBDIR)/templates
	install -m 644 local/build-script $(LOCALLIBDIR)/templates/
	install -m 644 local/result $(LOCALLIBDIR)/templates/
	install -m 644 local/source.files $(LOCALLIBDIR)/templates/
	install -m 644 local/source.git $(LOCALLIBDIR)/templates/
	install -m 644 local/source.cvs $(LOCALLIBDIR)/templates/
	install -m 644 local/source.svn $(LOCALLIBDIR)/templates/

%.sh: %.sh.in
	$(GENSCRIPT) $< $@

uninstall:
	# do not remove possibly valuable templates

doc:

install-doc:

