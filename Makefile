# Sandbox build (Linux / WSL)
#
# Prerequisites:
#   odin on PATH
#   SDL2 dev libs: sudo apt install libsdl2-dev
#
# Targets:
#   make debug       -> build/sandbox-debug
#   make run-debug   -> build and run
#   make release     -> build/sandbox-release
#
# Windows native: use ./build.ps1 (Odin vendor SDL2.lib + SDL2.dll copy).

NAME := sandbox
BIN_DEBUG := build/$(NAME)-debug
BIN_RELEASE := build/$(NAME)-release
FRAME_DIR := debug/frames

.PHONY: all debug release run-debug run-release gif clean check-deps

all: debug

check-deps:
	@command -v odin >/dev/null 2>&1 || { echo "odin not found on PATH"; exit 1; }
	@if command -v pkg-config >/dev/null 2>&1; then \
		pkg-config --exists sdl2 || { echo "SDL2 not found. Install: sudo apt install libsdl2-dev"; exit 1; }; \
	elif ! ldconfig -p 2>/dev/null | grep -q 'libSDL2-2\.0\.so'; then \
		echo "SDL2 not found. Install: sudo apt install libsdl2-dev"; exit 1; \
	fi

debug: check-deps
	mkdir -p build
	odin build . -out=$(BIN_DEBUG) -debug -vet

release: check-deps
	mkdir -p build
	odin build . -out=$(BIN_RELEASE) -o:speed -vet

run-debug: debug
	./$(BIN_DEBUG)

run-release: release
	./$(BIN_RELEASE)

gif:
	@if [ -d "$(FRAME_DIR)" ] && [ "$$(ls $(FRAME_DIR)/*.png 2>/dev/null | wc -l)" -gt 0 ]; then \
		if command -v magick >/dev/null 2>&1; then \
			magick -delay 5 -loop 0 $(FRAME_DIR)/frame_*.png debug/animation.gif; \
		elif command -v convert >/dev/null 2>&1; then \
			convert -delay 5 -loop 0 $(FRAME_DIR)/frame_*.png debug/animation.gif; \
		else \
			echo "ImageMagick not found. Install ImageMagick to generate GIF."; \
			exit 1; \
		fi; \
		echo "GIF saved: debug/animation.gif"; \
	else \
		echo "No frames in $(FRAME_DIR)/. Run the app and press SPACE to record first."; \
	fi

clean:
	rm -rf build debug/
