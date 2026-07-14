ROM := build/stella-was-together.bin

all: $(ROM)

$(ROM): src/main.asm src/vcs.h
	@mkdir -p build
	cd src && dasm main.asm -f3 -v0 -o../$(ROM) -l../build/main.lst -s../build/main.sym
	@ls -l $(ROM)
	@size=$$(wc -c < $(ROM)); \
	if [ $$size -ne 8192 ]; then \
		echo "ERROR: ROM is $$size bytes, expected exactly 8192 (F8 = 2 x 4K)"; \
		rm -f $(ROM); \
		exit 1; \
	fi
	@echo "ROM is exactly 8192 bytes — F8 layout intact"

run: $(ROM)
	stella $(ROM)

clean:
	rm -rf build

.PHONY: all run clean
