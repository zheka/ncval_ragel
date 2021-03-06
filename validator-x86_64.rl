/*
 * Copyright (c) 2011 The Native Client Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include <assert.h>
#include <elf.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "validator-x86_64.h"

#undef TRUE
#define TRUE    1

#undef FALSE
#define FALSE   0

#include "validator-x86_64-instruction-consts.c"

#define check_jump_dest \
    if ((jump_dest & bundle_mask) != bundle_mask) { \
      if (jump_dest >= size) { \
        printf("direct jump out of range: %zx\n", jump_dest); \
        result = 1; \
        goto error_detected; \
      } else { \
        BitmapSetBit(jump_dests, jump_dest + 1); \
      } \
    } \
    operand0 = JMP_TO; \
    base = REG_RIP; \
    index = REG_NONE;

%%{
  machine x86_64_decoder;
  alphtype unsigned char;

  action check_access {
    if ((base == REG_RIP) || (base == REG_RSP) ||
	(base == REG_RBP) || (base == REG_R15)) {
      if ((index == restricted_register) ||
	  ((index == REG_RDI) &&
	   (restricted_register == kSandboxedRsiRestrictedRdi))) {
	BitmapClearBit(valid_targets, begin - data);
      } else if ((index != REG_NONE) && (index != REG_RIZ)) {
	fprintf(stderr,"Improper sandboxing in instruction %zx", begin - data);
	exit(1);
      }
    } else if ((index == REG_RIP) || (index == REG_RSP) ||
	       (index == REG_RBP) || (index == REG_R15)) {
      if ((base == restricted_register) ||
	  ((base == REG_RDI) &&
	   (restricted_register == kSandboxedRsiRestrictedRdi))) {
	BitmapClearBit(valid_targets, begin - data);
      } else if ((base != REG_NONE) && (base != REG_RIZ)) {
	fprintf(stderr,"Improper sandboxing in instruction @%zx", begin - data);
	exit(1);
      }
    } else {
      fprintf(stderr,"Improper sandboxing in instruction @%zx", begin - data);
    }
  }

  action rel8_operand {
    int8_t offset = (uint8_t) (p[0]);
    size_t jump_dest = offset + (p - data);
    check_jump_dest;
  }
  action rel16_operand {
    assert(FALSE);
  }
  action rel32_operand {
    int32_t offset =
	   (uint32_t) (p[-3] + 256U * (p[-2] + 256U * (p[-1] + 256U * (p[0]))));
    size_t jump_dest = offset + (p - data);
    check_jump_dest;
  }

  include decode_x86_64 "validator-x86_64-instruction.rl";

  action process_normal_instruction {
    /* If Sandboxed Rsi is destroyed then we must note that.  */
    if (restricted_register == kSandboxedRsi) {
      for (i = 0; i < operands_count; ++i) {
	if ((operands[i].write == TRUE) &&
	    (operands[i].name == REG_RSI) &&
	    ((operands[i].type == OperandSandboxRestricted) ||
	     (operands[i].type == OperandSandboxUnrestricted))) {
	  restricted_register = kNoRestrictedReg;
	  break;
	}
      }
    }
    if (restricted_register == kSandboxedRsi) {
      for (i = 0; i < operands_count; ++i) {
	if ((operands[i].write == TRUE) &&
	    (operands[i].name == REG_RDI) &&
	    (operands[i].type == OperandSandboxRestricted)) {
	  restricted_register = kSandboxedRsiRestrictedRdi;
	}
      }
    }
    if (restricted_register != kSandboxedRsiRestrictedRdi) {
      restricted_register = kNoRestrictedReg;
      for (i = 0; i < operands_count; ++i) {
	if (operands[i].write && operands[i].name <= REG_R15) {
	  if (operands[i].type == OperandSandboxRestricted) {
	    if (operands[i].name == REG_R15) {
	      printf("Incorrectly modified register %%r15 at the %zx\n",
								      p - data);
	      exit(1);
	    } else {
	      restricted_register = operands[i].name;
	    }
	  } else if (operands[i].type == OperandSandboxUnrestricted) {
	    if (operands[i].name == REG_RBP) {
	      printf("Incorrectly modified register %%rbp at the %zx\n",
								      p - data);
	      exit(1);
	    } else if (operands[i].name == REG_RSP) {
	      printf("Incorrectly modified register %%rsp at the %zx\n",
								      p - data);
	      exit(1);
	    } else if (operands[i].name == REG_R15) {
	      printf("Incorrectly modified register %%r15 at the %zx\n",
								      p - data);
	      exit(1);
	    }
	  } else if (operands[i].type == OperandNoSandboxEffect) {
	    if (operands[i].name == REG_R15) {
	      printf("Incorrectly modified register %%r15 at the %zx\n",
								      p - data);
	      exit(1);
	    }
	  }
        }
      }
    }
  }

  # Remove special instructions which are only allowed in special cases.
  normal_instruction = (one_instruction - (
    (0x4c 0x01 0xfd)		 | # add %r15,%rbp
    (0x49 0x8d 0x2c 0x2f)	 | # lea (%r15,%rbp,1),%rbp
    (0x4a 0x8d 0x6c 0x3d any)	 | # lea 0x0(%rbp,%r15,1),%rbp
    (0x4c 0x01 0xfc)		 | # add %r15,%rsp
    (0x4a 0x8d 0x24 0x3c)	 | # lea (%rsp,%r15,1),%rsp
    (0x49 0x8d 0x34 0x37)	 | # lea (%r15,%rsi,1),%rsi
    (0x49 0x8d 0x3c 0x3f)	 | # lea (%r15,%rdi,1),%rdi
    (0x48 0x89 0xe5)		 | # mov %rsp,%rbp
    (0x48 0x89 0xec)		   # mov %rbp,%rsp
  )) @process_normal_instruction;

  special_instruction =
    (0x4c 0x01 0xfd	       | # add %r15,%rbp
     0x49 0x8d 0x2c 0x2f       | # lea (%r15,%rbp,1),%rbp
     0x4a 0x8d 0x6c 0x3d 0x00)   # lea 0x0(%rbp,%r15,1),%rbp
    @{ if (restricted_register != REG_RBP) {
	 printf("Incorrectly sandboxed %%rbp at the %zx\n", p - data);
	 exit(1);
       }
       restricted_register = kNoRestrictedReg;
    } |
    (0x4c 0x01 0xfc	  | # add %r15,%rsp
     0x4a 0x8d 0x24 0x3c)   # lea (%rsp,%r15,1),%rsp
    @{ if (restricted_register != REG_RSP) {
	 printf("Incorrectly sandboxed %%rsp at the %zx\n", p - data);
	 exit(1);
       }
       restricted_register = kNoRestrictedReg;
    } |
    (0x49 0x8d 0x34 0x37) # lea (%r15,%rsi,1),%rsi
    @{ if (restricted_register == REG_RSI) {
	 restricted_register = kSandboxedRsi;
       } else {
	 restricted_register = kNoRestrictedReg;
       }
    } |
    (0x49 0x8d 0x3c 0x3f) # lea (%r15,%rdi,1),%rdi
    @{ if (restricted_register == REG_RDI) {
	 restricted_register = kSandboxedRdi;
       } else if (restricted_register == kSandboxedRsiRestrictedRdi) {
	 restricted_register = kSandboxedRsiSandboxedRdi;
       } else {
         restricted_register = kNoRestrictedReg;
       }
    } |
    (0x48 0x89 0xe5) # mov %rsp,%rbp
    @{ if (restricted_register == REG_RSP) {
	  printf("Incorrectly modified register %%rsp at the %zx\n", p - data);
	  exit(1);
       }
       restricted_register = kNoRestrictedReg;
    } |
    (0x48 0x89 0xec) # mov %rbp,%rsp
    @{ if (restricted_register == REG_RBP) {
	  printf("Incorrectly modified register %%rbp at the %zx\n", p - data);
	  exit(1);
       }
       restricted_register = kNoRestrictedReg;
    };

  main := ((normal_instruction | special_instruction) >{
	begin = p;
	BitmapSetBit(valid_targets, p - data);
	rex_prefix = FALSE;
	vex_prefix2 = 0xe0;
	vex_prefix3 = 0x00;
     })*
    $!{ process_error(p, userdata);
	result = 1;
	goto error_detected;
    };

}%%

%% write data;

/* Ignore this information for now.  */
#define data16_prefix if (0) result
#define lock_prefix if (0) result
#define repz_prefix if (0) result
#define repnz_prefix if (0) result
#define branch_not_taken if (0) result
#define branch_taken if (0) result
#define imm if (0) begin
#define imm_operand if (0) result
#define imm2 if (0) begin
#define imm2_operand if (0) result
#define scale if (0) result
#define disp if (0) begin
#define disp_type if (0) result
#define operand0 operands[0].name
#define operand1 operands[1].name
#define operand2 operands[2].name
#define operand3 operands[3].name
#define operand4 operands[4].name
#define operand0_type operands[0].type
#define operand1_type operands[1].type
#define operand2_type operands[2].type
#define operand3_type operands[3].type
#define operand4_type operands[4].type
/* It's not important for us.  */
#define operand0_read if (0) result
#define operand1_read if (0) result
#define operand2_read if (0) result
#define operand3_read if (0) result
#define operand4_read if (0) result
#define operand0_write operands[0].write
#define operand1_write operands[1].write
#define operand2_write operands[2].write
#define operand3_write operands[3].write
#define operand4_write operands[4].write

enum {
  REX_B = 1,
  REX_X = 2,
  REX_R = 4,
  REX_W = 8
};

enum disp_mode {
  DISPNONE,
  DISP8,
  DISP16,
  DISP32,
  DISP64,
};

enum imm_mode {
  IMMNONE,
  IMM2,
  IMM8,
  IMM16,
  IMM32,
  IMM64
};

static const uint8_t one = 1;

static const int kBitsPerByte = 8;

static inline uint8_t *BitmapAllocate(uint32_t indexes) {
  uint32_t byte_count = (indexes + kBitsPerByte - 1) / kBitsPerByte;
  uint8_t *bitmap = malloc(byte_count);
  if (bitmap != NULL) {
    memset(bitmap, 0, byte_count);
  }
  return bitmap;
}

static inline int BitmapIsBitSet(uint8_t *bitmap, uint32_t index) {
  return (bitmap[index / kBitsPerByte] & (1 << (index % kBitsPerByte))) != 0;
}

static inline void BitmapSetBit(uint8_t *bitmap, uint32_t index) {
  bitmap[index / kBitsPerByte] |= 1 << (index % kBitsPerByte);
}

static inline void BitmapClearBit(uint8_t *bitmap, uint32_t index) {
  bitmap[index / kBitsPerByte] &= ~(1 << (index % kBitsPerByte));
}

int CheckJumpTargets(uint8_t *valid_targets, uint8_t *jump_dests,
                     size_t size) {
  size_t i;
  for (i = 0; i < size / 32; i++) {
    uint32_t jump_dest_mask = ((uint32_t *) jump_dests)[i];
    uint32_t valid_target_mask = ((uint32_t *) valid_targets)[i];
    if ((jump_dest_mask & ~valid_target_mask) != 0) {
      printf("bad jump to around %x\n", (unsigned)(i * 32));
      return 1;
    }
  }
  return 0;
}

int ValidateChunk(const uint8_t *data, size_t size,
		  process_error_func process_error, void *userdata) {
  const size_t bundle_size = 32;
  const size_t bundle_mask = bundle_size - 1;

  uint8_t *valid_targets = BitmapAllocate(size);
  uint8_t *jump_dests = BitmapAllocate(size);

  const uint8_t *p = data;
  const uint8_t *begin;

  uint8_t rex_prefix, vex_prefix2, vex_prefix3;
  struct Operand {
    unsigned int name	:5;
    unsigned int type	:2;
    bool	 write	:1;
  } operands[5];
  int result = 0;
  enum register_name base, index;
  uint8_t operands_count, i;

  assert(size % bundle_size == 0);

  while (p < data + size) {
    const uint8_t *pe = p + bundle_size;
    const uint8_t *eof = pe;
    int cs;
    enum {
      kNoRestrictedReg = 32,
      kSandboxedRsi,
      kSandboxedRdi,
      kSandboxedRsiRestrictedRdi,
      kSandboxedRsiSandboxedRdi
    }; uint8_t restricted_register = kNoRestrictedReg;

    %% write init;
    %% write exec;

    if (restricted_register == REG_RBP) {
      printf("Incorrectly sandboxed %%rbp at the %d%zx\n", *data, p - data);
      exit(1);
    } else if (restricted_register == REG_RSP) {
      printf("Incorrectly sandboxed %%rbp at the %zx\n", p - data);
      exit(1);
    }
  }

  if (CheckJumpTargets(valid_targets, jump_dests, size)) {
    result = 1;
    goto error_detected;
  }

error_detected:
  return result;
}
