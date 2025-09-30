#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/socket.h>
#include <linux/filter.h>
#include <netinet/in.h>
#include <linux/ip.h>
#include <linux/tcp.h>
#include <string.h>
#include <errno.h>

#define FAKE_PID_FILE "/var/run/haldrund.pid"
#define FAKE_COMM "/usr/libexec/haldrund"

// Complex BPF program converted from assembly
struct sock_filter bpf_code[] = {
    /* 000 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 001 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 002 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 30),          // jneq #64,30
    /* 003 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 004 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 005 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 96, 0, 6),           // jneq #96,6
    /* 006 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 007 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 17, 9, 0),           // jeq #17,9
    /* 008 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 009 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 44, 0, 2),           // jneq #44,2
    /* 010 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 40),                   // ldb [40]
    /* 011 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 17, 5, 0),           // jeq #17,5
    /* 012 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 013 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 014 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 18),          // jneq #64,18
    /* 015 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 016 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 17, 0, 16),          // jneq #17,16
    /* 017 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 018 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 14, 0),       // jset #8191,14
    /* 019 */ BPF_STMT(BPF_LD + BPF_IMM, 8),                            // ld #8
    /* 020 */ BPF_STMT(BPF_ST, 0),                                      // st M[0]
    /* 021 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 022 */ BPF_STMT(BPF_LD + BPF_MEM, 0),                            // ld M[0]
    /* 023 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 024 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 025 */ BPF_STMT(BPF_LD + BPF_H + BPF_IND, 0),                    // ldh [x + 0]
    /* 026 */ BPF_STMT(BPF_ST, 1),                                      // st M[1]
    /* 027 */ BPF_STMT(BPF_LD + BPF_IMM, 29269),                        // ld #29269
    /* 028 */ BPF_STMT(BPF_ST, 2),                                      // st M[2]
    /* 029 */ BPF_STMT(BPF_LDX + BPF_MEM, 2),                           // ldx M[2]
    /* 030 */ BPF_STMT(BPF_LD + BPF_MEM, 1),                            // ld M[1]
    /* 031 */ BPF_STMT(BPF_ALU + BPF_SUB + BPF_X, 0),                   // sub x
    /* 032 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 0, 194, 0),          // jeq #0,194
    /* 033 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 034 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 035 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 45),          // jneq #64,45
    /* 036 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 037 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 038 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 42),          // jneq #64,42
    /* 039 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 040 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 1, 0, 40),           // jneq #1,40
    /* 041 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 042 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 38, 0),       // jset #8191,38
    /* 043 */ BPF_STMT(BPF_LD + BPF_IMM, 8),                            // ld #8
    /* 044 */ BPF_STMT(BPF_ST, 2),                                      // st M[2]
    /* 045 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 046 */ BPF_STMT(BPF_LD + BPF_MEM, 2),                            // ld M[2]
    /* 047 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 048 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 049 */ BPF_STMT(BPF_LD + BPF_H + BPF_IND, 0),                    // ldh [x + 0]
    /* 050 */ BPF_STMT(BPF_ST, 3),                                      // st M[3]
    /* 051 */ BPF_STMT(BPF_LD + BPF_IMM, 29269),                        // ld #29269
    /* 052 */ BPF_STMT(BPF_ST, 4),                                      // st M[4]
    /* 053 */ BPF_STMT(BPF_LDX + BPF_MEM, 4),                           // ldx M[4]
    /* 054 */ BPF_STMT(BPF_LD + BPF_MEM, 3),                            // ld M[3]
    /* 055 */ BPF_STMT(BPF_ALU + BPF_SUB + BPF_X, 0),                   // sub x
    /* 056 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 0, 0, 24),           // jneq #0,24
    /* 057 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 058 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 059 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 21),          // jneq #64,21
    /* 060 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 061 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 062 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 18),          // jneq #64,18
    /* 063 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 064 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 1, 0, 16),           // jneq #1,16
    /* 065 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 066 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 14, 0),       // jset #8191,14
    /* 067 */ BPF_STMT(BPF_LD + BPF_IMM, 0),                            // ld #0
    /* 068 */ BPF_STMT(BPF_ST, 4),                                      // st M[4]
    /* 069 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 070 */ BPF_STMT(BPF_LD + BPF_MEM, 4),                            // ld M[4]
    /* 071 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 072 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 073 */ BPF_STMT(BPF_LD + BPF_B + BPF_IND, 0),                    // ldb [x + 0]
    /* 074 */ BPF_STMT(BPF_ST, 5),                                      // st M[5]
    /* 075 */ BPF_STMT(BPF_LD + BPF_IMM, 8),                            // ld #8
    /* 076 */ BPF_STMT(BPF_ST, 6),                                      // st M[6]
    /* 077 */ BPF_STMT(BPF_LDX + BPF_MEM, 6),                           // ldx M[6]
    /* 078 */ BPF_STMT(BPF_LD + BPF_MEM, 5),                            // ld M[5]
    /* 079 */ BPF_STMT(BPF_ALU + BPF_SUB + BPF_X, 0),                   // sub x
    /* 080 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 0, 146, 0),          // jeq #0,146
    /* 081 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 082 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 083 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 67),          // jneq #64,67
    /* 084 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 085 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 086 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 64),          // jneq #64,64
    /* 087 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 088 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 089 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 96, 0, 6),           // jneq #96,6
    /* 090 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 091 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 9, 0),            // jeq #6,9
    /* 092 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 093 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 44, 0, 2),           // jneq #44,2
    /* 094 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 40),                   // ldb [40]
    /* 095 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 5, 0),            // jeq #6,5
    /* 096 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 097 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 098 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 52),          // jneq #64,52
    /* 099 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 100 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 0, 50),           // jneq #6,50
    /* 101 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 102 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 48, 0),       // jset #8191,48
    /* 103 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 104 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 105 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 96, 0, 6),           // jneq #96,6
    /* 106 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 107 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 9, 0),            // jeq #6,9
    /* 108 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 109 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 44, 0, 2),           // jneq #44,2
    /* 110 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 40),                   // ldb [40]
    /* 111 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 5, 0),            // jeq #6,5
    /* 112 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 113 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 114 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 36),          // jneq #64,36
    /* 115 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 116 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 0, 34),           // jneq #6,34
    /* 117 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 118 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 32, 0),       // jset #8191,32
    /* 119 */ BPF_STMT(BPF_LD + BPF_IMM, 12),                           // ld #12
    /* 120 */ BPF_STMT(BPF_ST, 6),                                      // st M[6]
    /* 121 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 122 */ BPF_STMT(BPF_LD + BPF_MEM, 6),                            // ld M[6]
    /* 123 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 124 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 125 */ BPF_STMT(BPF_LD + BPF_B + BPF_IND, 0),                    // ldb [x + 0]
    /* 126 */ BPF_STMT(BPF_ST, 7),                                      // st M[7]
    /* 127 */ BPF_STMT(BPF_LD + BPF_IMM, 240),                          // ld #240
    /* 128 */ BPF_STMT(BPF_ST, 8),                                      // st M[8]
    /* 129 */ BPF_STMT(BPF_LDX + BPF_MEM, 8),                           // ldx M[8]
    /* 130 */ BPF_STMT(BPF_LD + BPF_MEM, 7),                            // ld M[7]
    /* 131 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_X, 0),                   // and x
    /* 132 */ BPF_STMT(BPF_ST, 8),                                      // st M[8]
    /* 133 */ BPF_STMT(BPF_LD + BPF_IMM, 2),                            // ld #2
    /* 134 */ BPF_STMT(BPF_ST, 9),                                      // st M[9]
    /* 135 */ BPF_STMT(BPF_LDX + BPF_MEM, 9),                           // ldx M[9]
    /* 136 */ BPF_STMT(BPF_LD + BPF_MEM, 8),                            // ld M[8]
    /* 137 */ BPF_STMT(BPF_ALU + BPF_RSH + BPF_X, 0),                   // rsh x
    /* 138 */ BPF_STMT(BPF_ST, 9),                                      // st M[9]
    /* 139 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 140 */ BPF_STMT(BPF_LD + BPF_MEM, 9),                            // ld M[9]
    /* 141 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 142 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 143 */ BPF_STMT(BPF_LD + BPF_H + BPF_IND, 0),                    // ldh [x + 0]
    /* 144 */ BPF_STMT(BPF_ST, 10),                                     // st M[10]
    /* 145 */ BPF_STMT(BPF_LD + BPF_IMM, 21139),                        // ld #21139
    /* 146 */ BPF_STMT(BPF_ST, 11),                                     // st M[11]
    /* 147 */ BPF_STMT(BPF_LDX + BPF_MEM, 11),                          // ldx M[11]
    /* 148 */ BPF_STMT(BPF_LD + BPF_MEM, 10),                           // ld M[10]
    /* 149 */ BPF_STMT(BPF_ALU + BPF_SUB + BPF_X, 0),                   // sub x
    /* 150 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 0, 76, 0),           // jeq #0,76
    /* 151 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 152 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 153 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 74),          // jneq #64,74
    /* 154 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 155 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 156 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 71),          // jneq #64,71
    /* 157 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 158 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 159 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 96, 0, 6),           // jneq #96,6
    /* 160 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 161 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 9, 0),            // jeq #6,9
    /* 162 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 163 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 44, 0, 2),           // jneq #44,2
    /* 164 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 40),                   // ldb [40]
    /* 165 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 5, 0),            // jeq #6,5
    /* 166 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 167 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 168 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 59),          // jneq #64,59
    /* 169 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 170 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 0, 57),           // jneq #6,57
    /* 171 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 172 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 55, 0),       // jset #8191,55
    /* 173 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 174 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 175 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 96, 0, 6),           // jneq #96,6
    /* 176 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 177 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 9, 0),            // jeq #6,9
    /* 178 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 6),                    // ldb [6]
    /* 179 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 44, 0, 2),           // jneq #44,2
    /* 180 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 40),                   // ldb [40]
    /* 181 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 5, 0),            // jeq #6,5
    /* 182 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 0),                    // ldb [0]
    /* 183 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_K, 240),                 // and #240
    /* 184 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 64, 0, 43),          // jneq #64,43
    /* 185 */ BPF_STMT(BPF_LD + BPF_B + BPF_ABS, 9),                    // ldb [9]
    /* 186 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 6, 0, 41),           // jneq #6,41
    /* 187 */ BPF_STMT(BPF_LD + BPF_H + BPF_ABS, 6),                    // ldh [6]
    /* 188 */ BPF_JUMP(BPF_JMP + BPF_JSET + BPF_K, 8191, 39, 0),       // jset #8191,39
    /* 189 */ BPF_STMT(BPF_LD + BPF_IMM, 12),                           // ld #12
    /* 190 */ BPF_STMT(BPF_ST, 11),                                     // st M[11]
    /* 191 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 192 */ BPF_STMT(BPF_LD + BPF_MEM, 11),                           // ld M[11]
    /* 193 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 194 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 195 */ BPF_STMT(BPF_LD + BPF_B + BPF_IND, 0),                    // ldb [x + 0]
    /* 196 */ BPF_STMT(BPF_ST, 12),                                     // st M[12]
    /* 197 */ BPF_STMT(BPF_LD + BPF_IMM, 240),                          // ld #240
    /* 198 */ BPF_STMT(BPF_ST, 13),                                     // st M[13]
    /* 199 */ BPF_STMT(BPF_LDX + BPF_MEM, 13),                          // ldx M[13]
    /* 200 */ BPF_STMT(BPF_LD + BPF_MEM, 12),                           // ld M[12]
    /* 201 */ BPF_STMT(BPF_ALU + BPF_AND + BPF_X, 0),                   // and x
    /* 202 */ BPF_STMT(BPF_ST, 13),                                     // st M[13]
    /* 203 */ BPF_STMT(BPF_LD + BPF_IMM, 2),                            // ld #2
    /* 204 */ BPF_STMT(BPF_ST, 14),                                     // st M[14]
    /* 205 */ BPF_STMT(BPF_LDX + BPF_MEM, 14),                          // ldx M[14]
    /* 206 */ BPF_STMT(BPF_LD + BPF_MEM, 13),                           // ld M[13]
    /* 207 */ BPF_STMT(BPF_ALU + BPF_RSH + BPF_X, 0),                   // rsh x
    /* 208 */ BPF_STMT(BPF_ST, 14),                                     // st M[14]
    /* 209 */ BPF_STMT(BPF_LD + BPF_IMM, 26),                           // ld #26
    /* 210 */ BPF_STMT(BPF_ST, 15),                                     // st M[15]
    /* 211 */ BPF_STMT(BPF_LDX + BPF_MEM, 15),                          // ldx M[15]
    /* 212 */ BPF_STMT(BPF_LD + BPF_MEM, 14),                           // ld M[14]
    /* 213 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 214 */ BPF_STMT(BPF_ST, 15),                                     // st M[15]
    /* 215 */ BPF_STMT(BPF_LDX + BPF_B + BPF_MSH, 0),                   // ldx 4*([0]&0xf)
    /* 216 */ BPF_STMT(BPF_LD + BPF_MEM, 15),                           // ld M[15]
    /* 217 */ BPF_STMT(BPF_ALU + BPF_ADD + BPF_X, 0),                   // add x
    /* 218 */ BPF_STMT(BPF_MISC + BPF_TAX, 0),                          // tax
    /* 219 */ BPF_STMT(BPF_LD + BPF_W + BPF_IND, 0),                    // ld [x + 0]
    /* 220 */ BPF_STMT(BPF_ST, 0),                                      // st M[0]
    /* 221 */ BPF_STMT(BPF_LD + BPF_IMM, 960051513),                    // ld #960051513
    /* 222 */ BPF_STMT(BPF_ST, 1),                                      // st M[1]
    /* 223 */ BPF_STMT(BPF_LDX + BPF_MEM, 1),                           // ldx M[1]
    /* 224 */ BPF_STMT(BPF_LD + BPF_MEM, 0),                            // ld M[0]
    /* 225 */ BPF_STMT(BPF_ALU + BPF_SUB + BPF_X, 0),                   // sub x
    /* 226 */ BPF_JUMP(BPF_JMP + BPF_JEQ + BPF_K, 0, 0, 1),            // jneq #0,1
    /* 227 */ BPF_STMT(BPF_RET + BPF_K, 65535),                         // ret #65535
    /* 228 */ BPF_STMT(BPF_RET + BPF_K, 0),                             // ret #0
};

// Single signal handler that prints the received signal
void handle_signal(int sig) {
    printf("Received signal: %d\n", sig);
}

int main(int ac, char** av) {
    if (ac == 2 && strcmp(av[1], "clean") == 0) {
        puts("Cleaning fake BPFDoor...");
        return (unlink(FAKE_PID_FILE));
    }

    int debug = 0;
    if (ac == 2 && strcmp(av[1], "debug") == 0) {
        puts("Enabling debug mode...");
        debug = 1;
    }

    puts("Initializing fake BPFDoor...");

    puts("Check if already present...");
    if (!access(FAKE_PID_FILE, F_OK)) {
        // file already exist
        puts("fake BPFDoor already running");
        return (0);
    }

    puts("Hidding itself...");
    if (prctl(PR_SET_NAME, (unsigned long)FAKE_COMM, 0, 0, 0) != 0) {
        printf("prctl: %s\n", strerror(errno));
    }

    int fd = fork();
    if (fd < 0) {
        printf("fork: %s\n", strerror(errno));
        return (-1);
    } else if (fd > 0) {
        puts("Parent exiting...");
        exit(0);
    }
    // child:

    puts("New session...");
    if (setsid() < 0) {
        printf("setsid: %s\n", strerror(errno));
    }

    puts("Changing working dir...");
    if (chdir("/") < 0) {
        printf("chdir: %s\n", strerror(errno));
    }

    if (!debug) {
        puts("Closing fds...");
        int nullfd = openat(AT_FDCWD, "/dev/null", O_RDWR);
        if (nullfd < 0) {
            printf("openat: %s\n", strerror(errno));
            return (1);
        }
        close(0);
        close(1);
        close(2);
        dup2(nullfd, 0);
        dup2(nullfd, 1);
        dup2(nullfd, 2);
        close(3);
    }

    puts("Create fake pid file...");
    int pidfd = creat(FAKE_PID_FILE, 0644);
    if (pidfd < 0) {
        printf("fake pid file creation: %s\n", strerror(errno));
        return (-1);
    }
    close(pidfd);

    puts("Create socket...");
    int sock = socket(AF_INET, SOCK_RAW, IPPROTO_TCP);
    if (sock < 0) {
        printf("socket: %s\n", strerror(errno));
        return (-1);
    }

    puts("Attach BPF program...");
    struct sock_fprog bpf_prog = {
        .len = sizeof(bpf_code) / sizeof(bpf_code[0]),
        .filter = bpf_code,
    };
    if (setsockopt(sock, SOL_SOCKET, SO_ATTACH_FILTER, &bpf_prog, sizeof(bpf_prog)) < 0) {
        printf("setsockopt: %s\n", strerror(errno));
        return (-1);
    }

    puts("Receive data...");
    char buf[1024];
    while (1) {
        int recv = recvfrom(sock, buf, sizeof(buf), 0, NULL, NULL);
        if (recv < 0) {
            printf("recvfrom: %s\n", strerror(errno));
            return (-1);
        }
    }

    close(sock);
    return (0);
}
