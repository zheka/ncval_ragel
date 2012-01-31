# Copyright (c) 2012 The Native Client Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

# A temporary Makefile to build the DFA-based validator, decoder, tests.  This
# will likely go away as soon we integrate with the NaCl build system(s).

OUT = out
OUT_DIRS = $(OUT)/build/objs \
           $(OUT)/tarballs \
           $(OUT)/timestamps \
           $(OUT)/test
OBJD=$(OUT)/build/objs

PYTHON2X=/usr/bin/python2.6
CC = gcc -std=gnu99 -Wdeclaration-after-statement -Wall -pedantic -Wextra \
     -Wno-long-long -Wswitch-enum -Wsign-compare -Wno-variadic-macros -Werror \
     -O3 -finline-limit=10000 -m64
CXX = g++ -std=c++0x -O3 -finline-limit=10000 -m64
CFLAGS = -g
CXXFLAGS = -g
LDFLAGS = -g
INST_DEFS = general-purpose-instructions.def \
            system-instructions.def \
            x86-64-instructions.def \
            x87-instructions.def \
            mmx-instructions.def \
            xmm-instructions.def

FAST_TMP_FOR_TEST=/dev/shm

# Default rule.
all: $(OBJD)/decoder-test-x86_64 $(OBJD)/validator-test-x86_64

# Create all prerequisite directories.
$(OUT_DIRS):
	install -m 755 -d $@

# Pattern rules.
$(OBJD)/%.o: $(OBJD)/%.c
	$(CC) $(CFLAGS) -I. -I$(OBJD) -c $< -o $@

$(OBJD)/%.c: %.rl
	ragel -G2 -I$(OBJD) $< -o $@

$(OBJD)/%.c: $(OBJD)/%.rl
	ragel -G2 $<

$(OBJD)/%.dot: $(OBJD)/%.rl
	ragel -V $< -o $@

%.xml: %.rl
	ragel -x $< -o $@

# Decoder, validator, etc.
$(OBJD)/decoder-test-x86_64: \
    $(OBJD)/decoder-x86_64.o $(OBJD)/decoder-test-x86_64.o
$(OBJD)/validator-test-x86_64: \
    $(OBJD)/validator-x86_64.o $(OBJD)/validator-test-x86_64.o

GEN_DECODER=$(OBJD)/gen-decoder
$(GEN_DECODER): gen-decoder.C
	$(CXX) $(CXXFLAGS) -O0 $< -o $(GEN_DECODER)

$(OBJD)/decoder-x86_64.c: $(OBJD)/decoder-x86_64-instruction-consts.c
$(OBJD)/decoder-x86_64.c: $(OBJD)/decoder-x86_64-instruction.rl
$(OBJD)/decoder-x86_64-instruction-consts.c \
  $(OBJD)/decoder-x86_64-instruction.rl: $(GEN_DECODER) $(INST_DEFS)
	$(GEN_DECODER) -o $(OBJD)/decoder-x86_64-instruction.rl $(INST_DEFS) \
	    -d check_access,opcode,parse_operands_states,mark_data_fields

$(OBJD)/validator-x86_64.c: $(OBJD)/validator-x86_64-instruction-consts.c
$(OBJD)/validator-x86_64.c: $(OBJD)/validator-x86_64-instruction.rl
$(OBJD)/validator-x86_64-instruction-consts.c \
  $(OBJD)/validator-x86_64-instruction.rl: \
	$(GEN_DECODER) -o $(OBJD)/validator-x86_64-instruction.rl $(INST_DEFS) \
	  -d opcode,instruction_name,mark_data_fields,rel_operand_action \
	  nops.def

# Facilities for testing:
#   one-instruction.dot: the description of the DFA that accepts all instruction
#     the decoder is able to decode.
#   decoder-test-x86-64: the decoder that follows the objdump format
$(OBJD)/one-instruction.dot: one-instruction.rl \
  $(OBJD)/one-valid-instruction-consts.c $(OBJD)/one-valid-instruction.rl
	ragel -V -I$(OBJD) $< -o $@

$(OBJD)/one-valid-instruction-consts.c \
    $(OBJD)/one-valid-instruction.rl: $(GEN_DECODER) $(INST_DEFS)
	$(GEN_DECODER) -o $(OBJD)/one-valid-instruction.rl $(INST_DEFS) \
	  -d check_access,rex_prefix,vex_prefix,opcode,parse_operands \
	  -d parse_operands_states

$(OBJD)/decoder-test-x86_64.o: decoder-test-x86_64.c
	$(CC) $(CFLAGS) -c $< -o $@

# To test the decoder compare its output with output from objdump.  This
# allows to match instruction opcode, length and operands.
#
# Disassemblers in different versions of binutils produce slightly different
# output.  Do not take binutils as installed on the system, instead download and
# build it.
#
# Original source is located here:
# BINUTILS_URL_BASE = http://ftp.gnu.org/gnu/binutils
BINUTILS_URL_BASE = http://commondatastorage.googleapis.com/nativeclient-mirror/toolchain/binutils
BINUTILS_VER = binutils-2.22
BINUTILS_TARBALL = $(OUT)/tarballs/$(BINUTILS_VER).tar.bz2
BINUTILS_BUILD_DIR = $(OUT)/build/build-$(BINUTILS_VER)
BINUTILS_STAMP = $(OUT)/timestamps/binutils
OBJDUMP = $(BINUTILS_BUILD_DIR)/binutils/objdump
GAS = $(BINUTILS_BUILD_DIR)/gas/as-new

$(BINUTILS_TARBALL): | $(OUT_DIRS)
	rm -f $(BINUTILS_TARBALL)
	cd $(OUT)/tarballs && wget $(BINUTILS_URL_BASE)/$(BINUTILS_VER).tar.bz2

$(BINUTILS_STAMP): $(BINUTILS_TARBALL) | $(OUT_DIRS)
	rm -rf $(OBJD)/$(BINUTILS_VER)
	cd $(OBJD) && tar jxf ../tarballs/$(BINUTILS_VER).tar.bz2
	rm -rf $(BINUTILS_BUILD_DIR)
	mkdir -p $(BINUTILS_BUILD_DIR)
	cd $(BINUTILS_BUILD_DIR) && \
	  ../$(BINUTILS_VER)/configure
	$(MAKE) -C $(BINUTILS_BUILD_DIR)
	touch $@

.PHONY: binutils
binutils: $(BINUTILS_STAMP)

# Clean all build artifacts except the binutils' binaries.
.PHONY: clean
clean:
	rm -rf "$(OBJD)" "$(OUT)"/test \
	    "$(FAST_TMP_FOR_TEST)"/_test_dfa_insts*

# Clean everything not including the downloaded tarballs.
.PHONY: clean-all
clean-all: clean
	rm -rf "$(OUT)"/timestamps "$(OUT)"/build

# Clean side effects created while running tests.
.PHONY: clean-tests
	clean-tests:
	rm -rf "$(OUT)"/test "$(FAST_TMP_FOR_TEST)"/_test_dfa_insts*

.PHONY: check
check: $(BINUTILS_STAMP) one-instruction.xml decoder-test-x86_64 | $(OUT)/test
	python dfa_possibilities.py one-instruction.xml > $(OUT)/test/list.s
	$(GAS) --64 $(OUT)/test/list.s -o $(OUT)/test/list.o
	$(OBJDUMP) -d $(OUT)/test/list.o > $(OUT)/test/objdump.txt
	./decoder-test-x86_64 $(OUT)/test/list.o > $(OUT)/test/decoder.txt
	diff -uNr $(OUT)/test/objdump.txt $(OUT)/test/decoder.txt

.PHONY: check-n
check-n: $(BINUTILS_STAMP) $(OBJD)/one-instruction.dot \
    $(OBJD)/decoder-test-x86_64 | $(OUT)/test
	$(PYTHON2X) parse_dfa.py <"$(OBJD)/one-instruction.dot" \
	    > "$(OUT)/test/test_dfa_transitions.c"
	$(CC) $(CFLAGS) -c test_dfa.c -o "$(OUT)/test/test_dfa.o"
	$(CC) $(CFLAGS) -O0 -I. -c "$(OUT)/test/test_dfa_transitions.c" -o \
	    "$(OUT)/test/test_dfa_transitions.o"
	$(CC) $(LDFLAGS) "$(OUT)/test/test_dfa.o" \
	    "$(OUT)/test/test_dfa_transitions.o" -o $(OUT)/test/test_dfa
	$(PYTHON2X) run_objdump_test.py \
	  --gas="$(GAS)" \
	  --objdump="$(OBJDUMP)" \
	  --decoder="$(OBJD)/decoder-test-x86_64" \
	  --tester=./decoder_test_one_file.sh \
	  --nthreads=`cat /proc/cpuinfo | grep processor | wc -l` -- \
	  "$(OUT)/test/test_dfa" "$(FAST_TMP_FOR_TEST)"
