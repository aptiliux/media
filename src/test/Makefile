PROGRAM = ../../media_test
all: $(PROGRAM)

-include ../../configure.mk

VALA_LDFLAGS = `pkg-config --libs $(EXT_PKGS)`

SRC_FILES = \
	test.vala \
	marina/ProjectLoading.vala \
	../marina/ProjectLoader.vala \
	../marina/Logging.vala \
	../marina/util.vala

ifndef BUILD_DIR
BUILD_DIR=debug
endif

-include ../../marina.mk
HEADER_DIRS += ../marina

clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(PROGRAM)-$(VERSION)
	rm -f $(PROGRAM)

cleantemps:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)


