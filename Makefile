default: all

BUILD_ROOT = 1

VERSION = 0.1.0
FILLMORE = fillmore
LOMBARD = lombard
MEDIA_TEST = media_test

SRC_PREFIX=MARINA_
-include src/marina/sources.mk
DIST_SRC_FILES = $(foreach src,$(MARINA_SRC_FILES), src/marina/$(src))

SRC_PREFIX=LOMBARD_
-include src/lombard/sources.mk
DIST_SRC_FILES += $(foreach src, $(LOMBARD_SRC_FILES), src/lombard/$(src))

SRC_PREFIX=FILLMORE_
-include src/fillmore/sources.mk
DIST_SRC_FILES += $(foreach src, $(FILLMORE_SRC_FILES), src/fillmore/$(src))

SRC_PREFIX=TEST_
-include src/test/sources.mk
DIST_SRC_FILES += $(foreach src, $(TEST_SRC_FILES), src/test/$(src))

TEXT_FILES = \
	AUTHORS \
	COPYING \
	INSTALL \
	MAINTAINERS \
	NEWS \
	README \
	THANKS

DIST_MAKEFILES = \
	Makefile \
	marina.mk \
	src/marina/Makefile \
	src/marina/sources.mk \
	src/fillmore/Makefile \
	src/fillmore/sources.mk \
	src/lombard/Makefile \
	src/lombard/sources.mk \
	src/test/Makefile \
	src/test/sources.mk

DIST_NAME = media
DIST_FILES = $(DIST_MAKEFILES) configure minver $(DIST_SRC_FILES) $(EXPANDED_VAPI_FILES) \
	$(EXPANDED_SRC_HEADER_FILES) $(EXPANDED_RESOURCE_FILES) $(TEXT_FILES) resources/* misc/*

DIST_TAR = $(DIST_NAME)-$(VERSION).tar
DIST_TAR_BZ2 = $(DIST_TAR).bz2
DIST_TAR_GZ = $(DIST_TAR).gz
PACKAGE_ORIG_GZ = $(DIST_NAME)_`parsechangelog | grep Version | sed 's/.*: //'`.orig.tar.gz

MARINA = marina/libmarina.a
.PHONY: $(FILLMORE)
.PHONY: $(LOMBARD)
.PHONY: $(MEDIA_TEST)
.PHONY: $(MARINA)

$(MARINA):
	export VERSION=$(VERSION); $(MAKE) --directory=src/marina

$(FILLMORE): $(MARINA)
	export PROGRAM_NAME=$(FILLMORE); $(MAKE) --directory=src/fillmore

install: install-$(FILLMORE) install-$(LOMBARD)
	

uninstall: uninstall-$(FILLMORE) uninstall-$(LOMBARD)
	

install-$(FILLMORE): $(FILLMORE)
	export PROGRAM_NAME=$(FILLMORE); \
	$(MAKE) --directory=src/fillmore install; \

uninstall-$(FILLMORE):
	export PROGRAM_NAME=$(FILLMORE); \
	$(MAKE) --directory=src/fillmore uninstall; \

$(LOMBARD): $(MARINA)
	export PROGRAM_NAME=$(LOMBARD); \
	$(MAKE) --directory=src/lombard; \

install-$(LOMBARD): $(LOMBARD)
	export PROGRAM_NAME=$(LOMBARD); \
	$(MAKE) --directory=src/lombard install; \

uninstall-$(LOMBARD):
	export PROGRAM_NAME=$(LOMBARD); \
	$(MAKE) --directory=src/lombard uninstall; \

$(MEDIA_TEST):
	export PROGRAM_NAME=$(MEDIA_TEST); \
	$(MAKE) --directory=src/test;

all: $(FILLMORE) $(LOMBARD) $(MEDIA_TEST)
	

clean:
	$(MAKE) --directory=src/marina clean
	export PROGRAM_NAME=$(FILLMORE); $(MAKE) --directory=src/fillmore clean
	export PROGRAM_NAME=$(LOMBARD); $(MAKE) --directory=src/lombard clean
	export PROGRAM_NAME=$(MEDIA_TEST); $(MAKE) --directory=src/test clean

dist: $(DIST_FILES)
	mkdir -p $(DIST_NAME)-$(VERSION)
	cp --parents $(DIST_FILES) $(DIST_NAME)-$(VERSION)
	tar --bzip2 -cvf $(DIST_TAR_BZ2) $(DIST_NAME)-$(VERSION)
	tar --gzip -cvf $(DIST_TAR_GZ) $(DIST_NAME)-$(VERSION)
	rm -rf $(DIST_NAME)-$(VERSION)

distclean: clean
	rm -f configure.mk

