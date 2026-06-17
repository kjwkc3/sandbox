NAME := sandbox
BIN_DEBUG := build/$(NAME)-debug
BIN_RELEASE := build/$(NAME)-release
FRAME_DIR := debug/frames

.PHONY: all debug release run-debug run-release gif clean

all: debug

debug:
	mkdir -p build
	odin build . -out=$(BIN_DEBUG) -debug -vet

release:
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
