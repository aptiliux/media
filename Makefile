# Makefile for Lombard Video Editor

OUTPUT_FILE = lom

LOMBARD_SOURCES = \
	ui_app.vala \
    ui_timeline.vala \
    ui_track.vala \
    ui_clip.vala \
    clip.vala \
    track.vala \
    util.vala

MARINA_SOURCES = project.vala

LOMBARD_FILES = $(foreach src, $(LOMBARD_SOURCES), lombard/$(src))
MARINA_FILES = $(foreach src, $(MARINA_SOURCES), marina/$(src))

LIBS =  --pkg gdk-x11-2.0 \
        --pkg gee-1.0 \
        --pkg gstreamer-0.10 \
        --pkg gstreamer-pbutils-0.10 \
        --pkg gstreamer-interfaces-0.10 \
        --pkg gtk+-2.0 \
        --pkg glib-2.0

all: $(OUTPUT_FILE)

$(OUTPUT_FILE): $(LOMBARD_FILES) $(MARINA_FILES) Makefile
	valac $(LIBS) $(LOMBARD_FILES) $(MARINA_FILES) -o $(OUTPUT_FILE)

clean:
	rm $(OUTPUT_FILE)

