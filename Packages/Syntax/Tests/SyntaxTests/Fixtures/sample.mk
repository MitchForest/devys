APP := devys
SOURCES := main.c util.c

all: build

build:
	cc -o $(APP) $(SOURCES)

clean:
	rm -f $(APP)
