VALAC = valac
MIN_VALAC_VERSION = 0.7.7

ifndef MARINA_VAPI
MARINA_VAPI = ../marina/marina/marina.vapi
endif

ifdef USE_MARINA_VAPI
TEMP_MARINA_VAPI = $(MARINA_VAPI)
endif

VAPI_DIRS = \
	../vapi

HEADER_DIRS = \
	../vapi

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
	gtk+-2.0 >= 2.14.4 \
	gee-1.0 >= 0.5.0 \
	gdk-x11-2.0 >= 2.18.3 \
	gstreamer-0.10 >= 0.10.25 \
	gstreamer-base-0.10 >= 0.10.25 \
	gstreamer-controller-0.10 >= 0.10.25 \
	gstreamer-interfaces-0.10 >= 0.10.25 \
	gstreamer-pbutils-0.10 >= 0.10.25

PKGS = $(EXT_PKGS) $(LOCAL_PKGS)

EXPANDED_SRC_FILES = $(foreach src,$(SRC_FILES),./$(src))
EXPANDED_C_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(notdir $(src:.vala=.c)))
EXPANDED_SAVE_TEMPS_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(notdir $(src:.vala=.vala.c)))
EXPANDED_OBJ_FILES = $(foreach src,$(SRC_FILES),$(BUILD_DIR)/$(notdir $(src:.vala=.o)))

EXPANDED_VAPI_FILES = $(foreach vapi,$(VAPI_FILES),vapi/$(vapi))
EXPANDED_SRC_HEADER_FILES = $(foreach header,$(SRC_HEADER_FILES),vapi/$(header))
EXPANDED_RESOURCE_FILES = $(foreach res,$(RESOURCE_FILES),ui/$(res))
VALA_STAMP = $(BUILD_DIR)/.stamp

VALA_CFLAGS = `pkg-config --cflags $(EXT_PKGS)` $(foreach hdir,$(HEADER_DIRS),-I$(hdir)) \
	$(foreach def,$(DEFINES),-D$(def))

# setting CFLAGS in configure.mk overrides build type
ifndef CFLAGS
ifdef BUILD_DEBUG
CFLAGS = -O0 -g -pipe
else
CFLAGS = -O2 -g -pipe -mfpmath=sse -march=nocona
endif
endif

VALAFLAGS = -g --enable-checking --thread $(USER_VALAFLAGS)

# Do not remove hard tab or at symbol; necessary for dependencies to complete.  (Possible make
# bug.)
$(EXPANDED_C_FILES): $(VALA_STAMP)
	@

$(EXPANDED_OBJ_FILES): %.o: %.c $(CONFIG_IN) Makefile
	$(CC) -c $(VALA_CFLAGS) $(CFLAGS) -o $@ $<

$(VALA_STAMP): $(EXPANDED_SRC_FILES) $(EXPANDED_VAPI_FILES) $(EXPANDED_SRC_HEADER_FILES) Makefile \
	$(CONFIG_IN)
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
	@ bash -c "[ '`valac --version`' '>' 'Vala $(MIN_VALAC_VERSION)' ]" || bash -c "[ '`valac --version`' '==' 'Vala $(MIN_VALAC_VERSION)' ]" || ( echo '$(PROGRAM)$(LIBRARY) requires Vala compiler $(MIN_VALAC_VERSION) or greater.  You are running' `valac --version` '\b.'; exit 1 )
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
	$(CC) $(EXPANDED_OBJ_FILES) $(CFLAGS) $(VALA_LDFLAGS) -o $@
endif

