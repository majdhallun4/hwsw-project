IVERILOG ?= iverilog
VVP ?= vvp
SLANG ?= slang

.PHONY: all lint test test-nbody test-huffman clean

all: lint

lint:
	$(SLANG) --lint-only --top tb_nbody_pair_accel \
		nbody_pair_accel.sv tb_nbody_pair_accel.sv
	$(SLANG) --lint-only --top tb_huffman_decode_accel \
		huffman_decode_accel.sv tb_huffman_decode_accel.sv

test: test-nbody test-huffman

test-nbody:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_nbody_pair_accel -o build/tb_nbody_pair_accel \
		nbody_pair_accel.sv tb_nbody_pair_accel.sv
	$(VVP) build/tb_nbody_pair_accel

test-huffman:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_huffman_decode_accel -o build/tb_huffman_decode_accel \
		huffman_decode_accel.sv tb_huffman_decode_accel.sv
	$(VVP) build/tb_huffman_decode_accel

clean:
	rm -rf build
