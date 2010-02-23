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
	$(MAKE) --directory=src/fillmore

$(LOMBARD): $(MARINA)
	$(MAKE) --directory=src/lombard

$(MEDIA_TEST):
	$(MAKE) --directory=src/test
	
all: $(FILLMORE) $(LOMBARD) $(MEDIA_TEST)

clean:
	$(MAKE) --directory=src/marina clean
	$(MAKE) --directory=src/fillmore clean
	$(MAKE) --directory=src/lombard clean
	$(MAKE) --directory=src/test clean


