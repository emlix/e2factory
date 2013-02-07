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

TOPLEVEL = ../..

include $(TOPLEVEL)/make.vars

MANPAGES1 = \
e2factory.1 \
e2-build.1 \
e2-cf.1 \
e2-create-project.1 \
e2-dlist.1 \
e2-dsort.1 \
e2-fetch-project.1 \
e2-fetch-sources.1 \
e2-install-e2.1 \
e2-locate-project-root.1 \
e2-ls-project.1 \
e2-new-source.1 \
e2-playground.1

MANPAGES5 = \
e2.conf.5 \
e2chroot.5 \
e2env.5 \
e2licence.5 \
e2project.5 \
e2rc.5 \
e2result.5 \
e2source.5

MANPAGES = $(MANPAGES1) $(MANPAGES5)

CLEAN_FILES = *~ $(MANPAGES) man.tar.gz

.PHONY: all install install-local uninstall clean

all:

install: $(MANPAGES)
	mkdir -p $(DESTDIR)$(MANDIR)/man1 $(DESTDIR)$(MANDIR)/man5
	install -m644 $(MANPAGES1) $(DESTDIR)$(MANDIR)/man1
	install -m644 $(MANPAGES5) $(DESTDIR)$(MANDIR)/man5

uninstall:
	set -e; for x in $(MANPAGES1) ; \
		do rm -f $(DESTDIR)$(MANDIR)/man1/$$x ; done
	set -e; for x in $(MANPAGES5) ; \
		do rm -f $(DESTDIR)$(MANDIR)/man5/$$x ; done
	rmdir $(DESTDIR)$(MANDIR)/man1 || :
	rmdir $(DESTDIR)$(MANDIR)/man5 || :

local:

install-local: doc
	mkdir -p $(LOCALDOCDIR)/man/man1 $(LOCALDOCDIR)/man/man5
	install -m644 $(MANPAGES1) $(LOCALDOCDIR)/man/man1
	install -m644 $(MANPAGES5) $(LOCALDOCDIR)/man/man5

doc: $(MANPAGES)
	tar -czf man.tar.gz $(MANPAGES)

%: %.in
	sed s/@VERSION@/$(VERSION)/g $< > $@

install-doc:

clean:
	rm -f $(CLEAN_FILES)
	rm -fr html man

check:

localdist:

