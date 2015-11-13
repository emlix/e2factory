SUBDIRS    =
TOPLEVEL   = ../..

include $(TOPLEVEL)/make.vars

CLEAN_FILES = ldoc

.PHONY: all install install-local clean local uninstall doc install-doc

all: ldoc
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

install-doc:
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done

clean: clean-lua-5.1.3 clean-luafilesystem-1.6.2
	for s in $(SUBDIRS) ; do \
		$(MAKE) -C $$s $@ ;\
	done
	rm -f $(CLEAN_FILES)

lua-5.1.3:
	cp -Rp $(TOPLEVEL)/lua/lua-5.1.3 lua-5.1.3
	$(MAKE) -C lua-5.1.3/src clean
	$(MAKE) -C lua-5.1.3/src all MYCFLAGS="\
		-DLUA_USE_POSIX -DLUA_USE_DLOPEN \
		-DLUA_PATH_DEFAULT='\"\"' \
		 -DLUA_CPATH_DEFAULT='\"\"'" \
		 MYLIBS="-Wl,-E -ldl"

.PHONY: clean-lua-5.1.3
clean-lua-5.1.3:
	rm -rf lua-5.1.3

.PHONY: lfs
lfs: luafilesystem-1.6.2/src/lfs.so

luafilesystem-1.6.2/src/lfs.so:
	$(MAKE) -C luafilesystem-1.6.2 lib LUA_INC="$$PWD/lua-5.1.3/src"

.PHONY: clean-luafilesystem-1.6.2
clean-luafilesystem-1.6.2:
	$(MAKE) -C luafilesystem-1.6.2 clean

ldoc: lua-5.1.3 lfs ldoc.sh
	sed -e "s|@LDOC_BASE@|$$PWD|" < ldoc.sh > ldoc
	chmod a+x ldoc
