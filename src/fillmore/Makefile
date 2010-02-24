PROGRAM = ../../$(PROGRAM_NAME)
GLADE_NAME = ../../libfill.so

all: $(PROGRAM)

USE_MARINA_VAPI=1
-include ../../configure.mk

VALA_LDFLAGS = -lmarina -L../marina
VALA_LDFLAGS += `pkg-config --libs $(EXT_PKGS)`
MARINA_DEPEND = ../marina/libmarina.a

SRC_FILES = \
	audio_project.vala \
	fillmore.vala \
	FillmoreClassFactory.vala \
	header_area.vala \
	ProjectProperties.vala \
	trackinformation.vala

ifndef BUILD_DIR
BUILD_DIR=fillmore
endif

-include ../../marina.mk
HEADER_DIRS += ../marina

