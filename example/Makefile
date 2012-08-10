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

CLEAN_FILES = *~ *.so

DOWNLOAD = http://www.e2factory.org/source/example
E2FACTORY_GIT = http://git.e2factory.org/git/e2factory/e2factory.git

E2_CONFIG = /etc/e2/e2.conf.sample
export E2_CONFIG

CHROOTDIR   = $(LOCALSTATEDIR)/chroot
RESULTSDIR  = $(LOCALSTATEDIR)/results
RELEASESDIR = $(LOCALSTATEDIR)/releases
PROJECTSDIR = $(LOCALSTATEDIR)/projects
UPSTREAMDIR = $(LOCALSTATEDIR)/upstream

ifneq ($(E2_LOCAL_BRANCH),)
  E2_LOCAL_BRANCH_ENV = E2_LOCAL_BRANCH=$(E2_LOCAL_BRANCH)
endif
ifneq ($(E2_LOCAL_TAG),)
  E2_LOCAL_TAG_ENV = E2_LOCAL_TAG=$(E2_LOCAL_TAG)
endif
ifneq ($(E2_CONFIG),)
  E2_CONFIG_ENV = E2_CONFIG=$(E2_CONFIG)
endif

default: example

clean:
	rm -fr e2factory-example
	rm -fr e2factory.git
	rm -fr base.tar.gz
	rm -f $(CLEAN_FILES)

base.tar.gz:
	wget $(DOWNLOAD)/base.tar.gz

e2factory.git:
	git clone $(E2FACTORY_GIT) e2factory.git

fetch: base.tar.gz e2factory.git

install_example: fetch
	for d in $(CHROOTDIR) $(RESULTSDIR) $(RELEASESDIR) $(PROJECTSDIR) \
		$(UPSTREAMDIR) ; do \
		install -d -m 2775 -g ebs $$d ;\
	done
	install -m 644 base.tar.gz $(CHROOTDIR)/
	cp -r e2factory.git $(PROJECTSDIR)/
	# need 'env -i' here to avoid environment going from this build
	# process to the local build inside e2-fetch-project.
	env -i \
		PATH=$(PATH) \
		$(E2_CONFIG_ENV) \
		HOME=$(HOME) \
		USER=$(USER) \
		$(E2_LOCAL_BRANCH_ENV) \
		$(E2_LOCAL_TAG_ENV) \
		./setup_example.sh

uninstall_example:
	rm -fr $(PROJECTSDIR)/e2factory-example
	rm -fr $(PROJECTSDIR)/e2factory.git
	rm -f $(CHROOTDIR)/base.tar.gz

.PHONY: example install_example uninstall_example
