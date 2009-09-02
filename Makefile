default: all

BUILD_ROOT = 1

MARINA_TESTABLE_SOURCES =	ProjectLoader.vala \
							util.vala

MARINA_TESTABLE_FILES = $(foreach src, $(MARINA_TESTABLE_SOURCES), marina/$(src))

MARINA_SOURCES =	$(MARINA_TESTABLE_SOURCES) \
					clip.vala \
					import.vala \
					project.vala \
					track.vala \
					MultiFileProgress.vala \
					ClipLibraryView.vala \
					thumbnailsink.vala

# TODO: lombard/video_track.vala is temporarily included in Marina.  This should go away soon.
MARINA_FILES =  $(foreach src, $(MARINA_SOURCES), marina/$(src)) \
				lombard/video_track.vala
				
MARINA_C_FILES = $(MARINA_FILES:.vala=.c)

GLOBAL_LIBS = --pkg gee-1.0 --pkg gstreamer-0.10 --pkg gtk+-2.0 --pkg gstreamer-base-0.10

marina/marina.vapi marina/marina.h $(MARINA_C_FILES): $(MARINA_FILES) Makefile
	valac $(VFLAGS) -C --library marina/marina -H marina/marina.h $(GLOBAL_LIBS) $(MARINA_FILES)

FILLMORE = fill

FILLMORE_SOURCES = \
	audio_project.vala \
	fillmore.vala \
	header_area.vala \
	timeline.vala \
	trackinformation.vala

FILLMORE_FILES = $(foreach src, $(FILLMORE_SOURCES), fillmore/$(src))

$(FILLMORE): $(FILLMORE_FILES) marina/marina.vapi Makefile
	valac $(VFLAGS) -X -Imarina $(GLOBAL_LIBS) $(FILLMORE_FILES) \
		  marina/marina.vapi $(MARINA_C_FILES) -o $(FILLMORE)

LOMBARD = lom

LOMBARD_SOURCES = \
	ui_app.vala \
	ui_timeline.vala \
	ui_track.vala \
	ui_clip.vala \
	video_project.vala

LOMBARD_FILES = $(foreach src, $(LOMBARD_SOURCES), lombard/$(src))

LOMBARD_LIBS =  --pkg gdk-x11-2.0 \
				--pkg gstreamer-pbutils-0.10 \
				--pkg gstreamer-interfaces-0.10 \
				--pkg glib-2.0

$(LOMBARD): $(LOMBARD_FILES) marina/marina.vapi Makefile
	valac $(VFLAGS) -X -Imarina $(GLOBAL_LIBS) $(LOMBARD_LIBS) $(LOMBARD_FILES) \
		  marina/marina.vapi $(MARINA_C_FILES) -o $(LOMBARD)

MARINA_TEST_SOURCES = ProjectLoading.vala
MARINA_TEST_FILES = $(foreach src, $(MARINA_TEST_SOURCES), test/marina/$(src))

TEST_SOURCES = test.vala 
TEST_LIBS = --pkg gee-1.0 \
			--pkg gstreamer-0.10 \
			--pkg gtk+-2.0 \
			--pkg glib-2.0
			
TEST_FILES = $(foreach src, $(TEST_SOURCES), test/$(src))

TEST = media_test

$(TEST): $(MARINA_TESTABLE_FILES) $(MARINA_TEST_SUPPORT) $(TEST_FILES) $(MARINA_TEST_FILES) Makefile
	valac $(VFLAGS) $(TEST_LIBS) $(TEST_FILES) $(MARINA_TEST_FILES) $(MARINA_TESTABLE_FILES) \
		$(MARINA_TEST_SUPPORT) -o $(TEST)

all: $(FILLMORE) $(LOMBARD) $(MARINA)

clean:
	rm -f marina/marina.vapi marina/marina.h $(MARINA_C_FILES) $(FILLMORE) $(LOMBARD) $(TEST)

