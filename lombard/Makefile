PROGRAM = ../lom
all: $(PROGRAM)
USE_MARINA_VAPI=1
-include ../configure.mk

VALA_LDFLAGS = -lmarina -L../marina
VALA_LDFLAGS += `pkg-config --libs $(EXT_PKGS)`

SRC_FILES = \
	ui_app.vala \
	video_project.vala

ifndef BUILD_DIR
BUILD_DIR=lombard
endif

-include ../marina.mk
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


