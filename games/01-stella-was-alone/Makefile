ROM := build/stella-was-alone.bin

all: $(ROM)

$(ROM): src/main.asm src/vcs.h
	@mkdir -p build
	cd src && dasm main.asm -f3 -v0 -o../$(ROM) -l../build/main.lst -s../build/main.sym
	@ls -l $(ROM)

run: $(ROM)
	stella $(ROM)

clean:
	rm -rf build

.PHONY: all run clean
