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
	$(TOPLEVEL)/scripts/genscript.sh $< $@

uninstall:
	# do not remove possibly valuable templates

doc:

install-doc:

