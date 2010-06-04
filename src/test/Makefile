PROGRAM = ../../$(PROGRAM_NAME)
all: $(PROGRAM)

-include ../../configure.mk

VALA_LDFLAGS = `pkg-config --libs $(EXT_PKGS)`
-include sources.mk
SRC_FILES += \
	../marina/ProjectLoader.vala \
	../marina/Logging.vala \
	../marina/util.vala

ifndef BUILD_DIR
BUILD_DIR=debug
endif

-include ../../marina.mk
HEADER_DIRS += ../marina

