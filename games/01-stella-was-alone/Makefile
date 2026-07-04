ROM := build/stella-was-alone.bin

all: $(ROM)

$(ROM): src/main.asm src/vcs.h src/text.inc
	@mkdir -p build
	cd src && dasm main.asm -f3 -v0 -o../$(ROM) -l../build/main.lst -s../build/main.sym
	@ls -l $(ROM)
	python3 tools/check_levels.py $(ROM) build/main.sym src/main.asm

src/text.inc: tools/gentext.py
	python3 tools/gentext.py src/text.inc

run: $(ROM)
	stella $(ROM)

clean:
	rm -rf build

.PHONY: all run clean
