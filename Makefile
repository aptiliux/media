default: all

BUILD_ROOT = 1

FILLMORE = fillmore
LOMBARD = lombard
MEDIA_TEST = media_test

MARINA = marina/libmarina.a
.PHONY: $(FILLMORE)
.PHONY: $(LOMBARD)
.PHONY: $(MEDIA_TEST)
.PHONY: $(MARINA)

$(MARINA):
	$(MAKE) --directory=src/marina

$(FILLMORE): $(MARINA)
	export PROGRAM_NAME=$(FILLMORE); $(MAKE) --directory=src/fillmore

install: install-$(FILLMORE) install-$(LOMBARD)
	

uninstall: uninstall-$(FILLMORE) uninstall-$(LOMBARD)
	

install-$(FILLMORE): $(FILLMORE)
	export PROGRAM_NAME=$(FILLMORE); \
	$(MAKE) --directory=src/fillmore install; \

uninstall-$(FILLMORE):
	export PROGRAM_NAME=$(FILLMORE); \
	$(MAKE) --directory=src/fillmore uninstall; \

$(LOMBARD): $(MARINA)
	export PROGRAM_NAME=$(LOMBARD); \
	$(MAKE) --directory=src/lombard; \

install-$(LOMBARD): $(LOMBARD)
	export PROGRAM_NAME=$(LOMBARD); \
	$(MAKE) --directory=src/lombard install; \

uninstall-$(LOMBARD):
	export PROGRAM_NAME=$(LOMBARD); \
	$(MAKE) --directory=src/lombard uninstall; \

$(MEDIA_TEST):
	export PROGRAM_NAME=$(MEDIA_TEST); \
	$(MAKE) --directory=src/test;

all: $(FILLMORE) $(LOMBARD) $(MEDIA_TEST)
	

clean:
	$(MAKE) --directory=src/marina clean
	export PROGRAM_NAME=$(FILLMORE); $(MAKE) --directory=src/fillmore clean
	export PROGRAM_NAME=$(LOMBARD); $(MAKE) --directory=src/lombard clean
	export PROGRAM_NAME=$(MEDIA_TEST); $(MAKE) --directory=src/test clean

