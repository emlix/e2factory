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

MANPAGES1    = \
e2.1 \
e2-build.1 \
e2-cf.1 \
e2-create-project.1 \
e2-dlist.1 \
e2-dsort.1 \
e2-fetch-project.1 \
e2-fetch-sources.1 \
e2-install-e2.1 \
e2-ls-project.1 \
e2-new-source.1 \
e2-playground.1 \
e2ssh.1 \
e2.conf.5 \
e2-build-numbers.1

MANPAGES5 = e2rc.5 e2config.5
MANPAGES7 = e2global.7 e2intro.7 e2workflow.7
MANPAGES = $(MANPAGES1) $(MANPAGES5) $(MANPAGES7)

MANPAGES_HTML = $(MANPAGES:=.html)

CLEAN_FILES = *~ man.tar.gz $(MANPAGES_HTML)

.PHONY: html man doc install-doc

all:

install:
	mkdir -p $(DESTDIR)$(MANDIR)/man1 $(DESTDIR)$(MANDIR)/man5 $(DESTDIR)$(MANDIR)/man7
	install -m644 $(MANPAGES1) $(DESTDIR)$(MANDIR)/man1
	install -m644 $(MANPAGES5) $(DESTDIR)$(MANDIR)/man5
	install -m644 $(MANPAGES7) $(DESTDIR)$(MANDIR)/man7

uninstall:
	for x in $(MANPAGES1) ; do rm -f $(DESTDIR)$(MANDIR)/man1/$$x ; done
	for x in $(MANPAGES5) ; do rm -f $(DESTDIR)$(MANDIR)/man5/$$x ; done
	for x in $(MANPAGES7) ; do rm -f $(DESTDIR)$(MANDIR)/man7/$$x ; done
	rmdir $(DESTDIR)$(MANDIR)/man1 || :
	rmdir $(DESTDIR)$(MANDIR)/man5 || :
	rmdir $(DESTDIR)$(MANDIR)/man7 || :

doc: man.tar.gz
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

install-doc: doc
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	tar -C $(DOCDIR) -xzf man.tar.gz

clean:
	rm -f $(CLEAN_FILES)
	rm -fr html man

%.html: %
	man2html -r $< >$@

man.tar.gz: $(MANPAGES_HTML)
	mkdir -p html man/man1 man/man5 man/man7
	cp *.1.html man/man1/
	cp *.5.html man/man5/
	cp *.7.html man/man7/
	tar -czf man.tar.gz man
