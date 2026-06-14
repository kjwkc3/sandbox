NAME := hello-triangle
BIN := build/$(NAME)

.PHONY: all build run clean

all: build

build:
	odin build . -out=$(BIN) -vet

run: build
	./$(BIN)

clean:
	rm -rf $(BIN) debug/
