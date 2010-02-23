PROGRAM = ../../fillmore
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


