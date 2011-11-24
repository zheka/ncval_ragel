#ifndef _DECODER_X86_64_H_
#define _DECODER_X86_64_H_

#include <inttypes.h>

#ifdef __cplusplus
extern "C" {
#endif

enum operand_size {
  OperandSize8bit,
  OperandSize16bit,
  OperandSize32bit,
  OperandSize64bit,
  OperandSizeST,
  OperandSizeXMM,
};

enum register_name {
  REG_RAX,
  REG_RCX,
  REG_RDX,
  REG_RBX,
  REG_RSP,
  REG_RBP,
  REG_RSI,
  REG_RDI,
  REG_R8,
  REG_R9,
  REG_R10,
  REG_R11,
  REG_R12,
  REG_R13,
  REG_R14,
  REG_R15,
  REG_RM,	/* Address in memory via rm field.			      */
  REG_RIP,	/* RIP - used as base in x86-64 mode.			      */
  REG_RIZ,	/* EIZ/RIZ - used as "always zero index" register.	      */
  REG_IMM,	/* Fixed value in imm field.				      */
  REG_ES_RDI,	/* For string instructions: %es:(%rsi).			      */
  REG_DS_RSI,	/* For string instructions: %ds:(%rdi).			      */
  REG_PORT_DX,	/* 16-bit DX: for in/out instructions.			      */
  REG_NONE,	/* For modrm: both index and base can be absent.	      */
  JMP_TO	/* Operand is jump target address: usually %rip+offset.	      */
};

struct instruction {
  char *name;
  unsigned char operands_count;
  struct {
    unsigned char rex;	      /* Mostly to distingush cases like %ah vs %spl. */
    int data16:1;	      /* "Normal", non-rex prefixes. */
    int lock:1;
    int rep:1;		      /* rep and repe are used in different commands */
    int repe:1;
    int repne:1;
    int branch_not_taken:1;
    int branch_taken:1;
  } prefix;
  struct {
    enum register_name name;
    enum operand_size size;
  } operands[5];
  struct {
    enum register_name base;
    enum register_name index;
    int scale;
    int32_t offset;
  } rm;
  int64_t imm;
};

typedef void (*process_instruction_func) (uint8_t *begin, uint8_t *end,
					  struct instruction *instruction,
					  void *userdata);

typedef void (*process_error_func) (uint8_t *ptr, void *userdata);

int DecodeChunk(uint32_t load_addr, uint8_t *data, size_t size, 
		process_instruction_func process_instruction,
		process_error_func process_error, void *userdata);

#ifdef __cplusplus
}
#endif

#endif
