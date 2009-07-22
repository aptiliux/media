default: all

BUILD_ROOT = 1

MARINA_SOURCES =	project.vala \
					track.vala

MARINA_FILES = $(foreach src, $(MARINA_SOURCES), marina/$(src))

FILLMORE = fill

FILLMORE_SOURCES = \
	audioengine.vala \
	fillmore.vala \
	header_area.vala \
	project.vala \
	region.vala \
	timeline.vala \
	track.vala \
	trackinformation.vala \
	util.vala

FILLMORE_FILES = $(foreach src, $(FILLMORE_SOURCES), fillmore/$(src))

FILLMORE_LIBS = --pkg gee-1.0 --pkg gstreamer-0.10 --pkg gtk+-2.0

$(FILLMORE): $(FILLMORE_FILES) Makefile
	valac $(VFLAGS) $(FILLMORE_LIBS) $(FILLMORE_FILES) -o $(FILLMORE)

LOMBARD = lom

LOMBARD_SOURCES = \
	clip.vala \
	ui_app.vala \
	ui_timeline.vala \
	ui_track.vala \
	ui_clip.vala \
	util.vala \
	video_project.vala \
	video_track.vala

LOMBARD_FILES = $(foreach src, $(LOMBARD_SOURCES), lombard/$(src))

LOMBARD_LIBS =  --pkg gdk-x11-2.0 \
				--pkg gee-1.0 \
				--pkg gstreamer-0.10 \
				--pkg gstreamer-pbutils-0.10 \
				--pkg gstreamer-interfaces-0.10 \
				--pkg gtk+-2.0 \
				--pkg glib-2.0

$(LOMBARD): $(LOMBARD_FILES) $(MARINA_FILES) Makefile
	valac $(VFLAGS) $(LOMBARD_LIBS) $(LOMBARD_FILES) $(MARINA_FILES) -o $(LOMBARD)

all: $(FILLMORE) $(LOMBARD)

clean:
	rm -f $(FILLMORE) $(LOMBARD)

