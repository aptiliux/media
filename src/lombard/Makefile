PROGRAM = ../../$(PROGRAM_NAME)
all: $(PROGRAM)
USE_MARINA_VAPI=1
-include ../../configure.mk

VALA_LDFLAGS = -lmarina -L../marina
VALA_LDFLAGS += `pkg-config --libs $(EXT_PKGS)`
MARINA_DEPEND = ../marina/libmarina.a

-include sources.mk

ifndef BUILD_DIR
BUILD_DIR=lombard
endif

-include ../../marina.mk
HEADER_DIRS += ../marina

