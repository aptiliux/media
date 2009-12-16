default: all

BUILD_ROOT = 1

FILLMORE = fill
LOMBARD = lom
MEDIA_TEST = media_test

MARINA = marina/libmarina.a

$(MARINA):
	$(MAKE) --directory=marina

$(FILLMORE): $(MARINA)
	$(MAKE) --directory=fillmore

$(LOMBARD): $(MARINA)
	$(MAKE) --directory=lombard

$(MEDIA_TEST):
	$(MAKE) --directory=test
	
all: $(FILLMORE) $(LOMBARD) $(MEDIA_TEST)

clean:
	$(MAKE) --directory=marina clean
	$(MAKE) --directory=fillmore clean
	$(MAKE) --directory=lombard clean
	$(MAKE) --directory=test clean


