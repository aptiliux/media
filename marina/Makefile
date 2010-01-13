LIBRARY = libmarina.a
all: $(LIBRARY)

# defaults that may be overridden by configure.mk
BUILD_RELEASE=1

-include ../configure.mk

SRC_FILES = \
	AppDirs.vala \
	AudioMeter.vala \
	ClassFactory.vala \
	ClipLibraryView.vala \
	clip.vala \
	command.vala \
	DialogUtils.vala \
	import.vala \
	Logging.vala \
	MediaEngine.vala \
	MultiFileProgress.vala \
	ProjectLoader.vala \
	project.vala \
	Ruler.vala \
	singledecodebin.vala \
	StatusBar.vala \
	thumbnailsink.vala \
	timeline.vala \
	TimeSystem.vala \
	track.vala \
	TrackView.vala \
	ui_clip.vala \
	UndoManager.vala \
	util.vala \
	video_track.vala

HEADER_FILES = marina.h
LIBRARY_NAME = --library marina

ifndef BUILD_DIR
BUILD_DIR=marina
endif

-include ../marina.mk

clean:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)
	rm -rf $(LIBRARY)-$(VERSION)
	rm -f $(LIBRARY)
	rm -f $(BUILD_DIR)/marina.vapi
	rm -f marina.h

cleantemps:
	rm -f $(EXPANDED_C_FILES)
	rm -f $(EXPANDED_SAVE_TEMPS_FILES)
	rm -f $(EXPANDED_OBJ_FILES)
	rm -f $(VALA_STAMP)

