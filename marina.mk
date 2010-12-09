VALAC = valac
MIN_VALAC_VERSION = 0.9.3
# defaults that may be overridden by configure.mk
ifndef PREFIX
PREFIX=/usr/local
endif

INSTALL_PROGRAM = install
INSTALL_DATA = install -m 644

ifndef MARINA_VAPI
MARINA_VAPI = ../marina/marina/marina.vapi
endif

ifdef USE_MARINA_VAPI
TEMP_MARINA_VAPI = $(MARINA_VAPI)
endif

VAPI_DIRS = \
	../../vapi

HEADER_DIRS = \
	../../vapi

EXT_PKGS = \
	gee-1.0 \
	gdk-x11-2.0 \
	gstreamer-0.10 \
	gstreamer-base-0.10 \
	gstreamer-controller-0.10 \
	gstreamer-interfaces-0.10 \
	gstreamer-pbutils-0.10 \
	gtk+-2.0

EXT_PKG_VERSIONS = \
	gtk+-2.0 >= 2.18.0 \
	gee-1.0 >= 0.5.0 \
	gdk-x11-2.0 >= 2.18.3 \
	gstreamer-0.10 >= 0.10.28 \
	gstreamer-base-0.10 >= 0.10.28 \
	gstreamer-controller-0.10 >= 0.10.28 \
	gstreamer-interfaces-0.10 >= 0.10.28 \
	gstreamer-pbutils-0.10 >= 0.10.28

PKGS = $(EXT_PKGS) $(LOCAL_PKGS)

EXPANDED_SRC_FILES = $(foreach src,$(SRC_FILES),./$(src))
EXPANDED_C_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(notdir $(src:.vala=.c)))
EXPANDED_SAVE_TEMPS_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(notdir $(src:.vala=.vala.c)))
EXPANDED_OBJ_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(notdir $(src:.vala=.o)))

EXPANDED_VAPI_FILES = $(foreach vapi,$(VAPI_FILES),vapi/$(vapi))
EXPANDED_SRC_HEADER_FILES = $(foreach header,$(SRC_HEADER_FILES),vapi/$(header))
EXPANDED_RESOURCE_FILES = $(foreach res,$(RESOURCE_FILES),ui/$(res))
VALA_STAMP = $(BUILD_DIR)/.stamp

ifdef PROGRAM
DEFINES = _PROGRAM_NAME='"$(PROGRAM_NAME)"'
endif

ifdef LIBRARY
DEFINES = _VERSION='"$(VERSION)"' _PREFIX='"$(PREFIX)"'
endif

VALA_CFLAGS = `pkg-config --cflags $(EXT_PKGS)` $(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -O0 -g -pipe -fPIC
else
CFLAGS = -O2 -g -pipe -fPIC
endif
endif

VALAFLAGS = -g --enable-checking --thread $(USER_VALAFLAGS)

# We touch the C file so that we have a better chance of a valid executable.  Bug #1778
$(EXPANDED_C_FILES): $(VALA_STAMP)
	touch $@

$(EXPANDED_OBJ_FILES): %.o: %.c $(CONFIG_IN) Makefile
	$(CC) -c $(VALA_CFLAGS) $(CFLAGS) -o $@ $<

install:
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) $(PROGRAM) $(DESTDIR)$(PREFIX)/bin
	mkdir -p $(DESTDIR)$(PREFIX)/share/$(PROGRAM_NAME)/resources
	$(INSTALL_DATA) ../../resources/* $(DESTDIR)$(PREFIX)/share/$(PROGRAM_NAME)/resources
	mkdir -p $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
	$(INSTALL_DATA) ../../resources/$(PROGRAM_NAME).svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps
ifndef DISABLE_ICON_UPDATE
	-gtk-update-icon-cache -f -t $(DESTDIR)$(PREFIX)/share/icons/hicolor || :
endif
	mkdir -p $(DESTDIR)$(PREFIX)/share/applications
	$(INSTALL_DATA) ../../misc/$(PROGRAM_NAME).desktop $(DESTDIR)$(PREFIX)/share/applications
ifndef DISABLE_DESKTOP_UPDATE
	-update-desktop-database || :
endif
	mkdir -p $(DESTDIR)$(PREFIX)/share/mime/packages
	$(INSTALL_DATA) ../../misc/$(PROGRAM_NAME).xml $(DESTDIR)$(PREFIX)/share/mime/packages
ifndef DISABLE_MIME_UPDATE
	-update-mime-database $(DESTDIR)$(PREFIX)/share/mime
endif

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(PROGRAM_NAME)
	rm -fr $(DESTDIR)$(PREFIX)/share/$(PROGRAM_NAME)
	rm -fr $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/$(PROGRAM_NAME).svg
	rm -f $(DESTDIR)$(PREFIX)/share/applications/$(PROGRAM_NAME).desktop
	rm -f $(DESTDIR)$(PREFIX)/share/mime/packages/$(PROGRAM_NAME).xml
ifndef DISABLE_MIME_UPDATE
	-update-mime-database $(DESTDIR)$(PREFIX)/share/mime
endif

$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(EXPANDED_SRC_HEADER_FILES) Makefile \
	$(CONFIG_IN) $(TEMP_MARINA_VAPI)
ifndef PROGRAM
ifndef LIBRARY
	@echo 'You must define either PROGRAM or LIBRARY in makefile'; exit 1
endif
endif
ifdef PROGRAM
ifdef LIBRARY
	@echo 'Both program and library are defined.  This is invalid.'; exit 1
endif
endif
	@ ../../minver `valac --version | awk '{print $$2}'` $(MIN_VALAC_VERSION) || ( echo '$(PROGRAM)$(LIBRARY) requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' `valac --version` '\b.'; exit 1 )
ifndef ASSUME_PKGS
ifdef EXT_PKG_VERSIONS
	pkg-config --print-errors --exists '$(EXT_PKG_VERSIONS)'
else ifdef EXT_PKGS
	pkg-config --print-errors --exists $(EXT_PKGS)
endif
endif
	mkdir -p $(BUILD_DIR)
	$(VALAC) $(LIBRARY_NAME) --ccode --directory=$(BUILD_DIR) --basedir=src $(VALAFLAGS) \
	$(foreach header,$(HEADER_FILES), -H $(header)) \
	$(foreach pkg,$(PKGS),--pkg=$(pkg)) \
	$(foreach vapidir,$(VAPI_DIRS),--vapidir=$(vapidir)) \
	$(foreach def,$(DEFINES),-X -D$(def)) \
	$(foreach hdir,$(HEADER_DIRS),-X -I$(hdir)) \
	$(VAPI_FILES) \
	$(VALA_DEFINES) \
	$(TEMP_MARINA_VAPI) \
	$(EXPANDED_SRC_FILES)
	touch $@

ifdef LIBRARY
$(LIBRARY): $(EXPANDED_OBJ_FILES) $(RESOURCES) 
	$(AR) $(ARFLAGS) $@ $?
endif

ifdef PROGRAM
$(PROGRAM): $(EXPANDED_OBJ_FILES) $(MARINA_DEPEND)
	$(CC) $(EXPANDED_OBJ_FILES) -lm $(CFLAGS) $(VALA_LDFLAGS) -export-dynamic -o $@
ifdef GLADE_NAME
	$(CC) $(EXPANDED_OBJ_FILES) -lm $(CFLAGS) $(VALA_LDFLAGS) -export-dynamic -shared -o $(GLADE_NAME)
endif
clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(PROGRAM)-$(VERSION)
	rm -f $(PROGRAM)
ifdef GLADE_NAME
	rm -f $(GLADE_NAME)
endif
endif


cleantemps:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)

