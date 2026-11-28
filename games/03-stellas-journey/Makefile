ROM := build/proto1.bin

all: $(ROM) check

# Prototype 1, the tall room (DESIGN-KICKOFF.md). The room's playfield
# and boxes are generated from one list of boxes (tools/genroom.py),
# which fails the build if anything drawn is not solid.
src/room1.inc: tools/genroom.py src/proto1.asm
	python3 tools/genroom.py src/proto1.asm src/room1.inc

$(ROM): src/proto1.asm src/room1.inc src/vcs.h
	@mkdir -p build
	cd src && dasm proto1.asm -f3 -v0 -o../$(ROM) -l../build/proto1.lst -s../build/proto1.sym
	@size=$$(wc -c < $(ROM)); \
	if [ $$size -ne 16384 ]; then \
		echo "ERROR: ROM is $$size bytes, expected 16384 (F6 = 4 x 4K)"; \
		rm -f $(ROM); exit 1; \
	fi

# Run the ROM headlessly (tools/check_proto1.py): every frame 262 lines,
# no drawn line past its 76 cycles, the stack clear of the variables,
# the view following the held character, and every character drawn
# where it stands, checked on pictures replayed from the TIA writes.
check: $(ROM)
	python3 tools/check_proto1.py $(ROM) build/proto1.sym

# Pictures of the prototype, from the ROM's own TIA writes.
pictures: $(ROM)
	python3 tools/picture.py $(ROM) build/proto1.sym build/pictures

room:
	python3 tools/genroom.py src/proto1.asm src/room1.inc --show

.PHONY: all check pictures room
