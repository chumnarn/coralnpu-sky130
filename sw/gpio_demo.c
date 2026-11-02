// SPDX-License-Identifier: Apache-2.0
// gpio_demo.c - first program for the CoralNPU SKY130 chip.
//
// The chip's AXI-manager port is terminated by axi_gpio_slave
// (rtl/soc/axi_gpio_slave.v), visible to software at 0x8000_0000:
//   +0x0 GPIO_OUT (RW, 8 bit)  +0x4 GPIO_IN (RO, 4 bit)
//   +0x8 SCRATCH  (RW, 32 bit) +0xC ID      (RO, 0xC0A15130)
#include <stdint.h>

#define GPIO_BASE 0x80000000u
#define REG(off) (*(volatile uint32_t*)(GPIO_BASE + (off)))
#define GPIO_OUT REG(0x0)
#define GPIO_IN  REG(0x4)
#define SCRATCH  REG(0x8)
#define GPIO_ID  REG(0xC)

static void delay(volatile uint32_t n) {
  while (n--) {
  }
}

int main(void) {
  if (GPIO_ID != 0xC0A15130u) {
    GPIO_OUT = 0xEE;  // wrong ID -> error pattern
    return 1;
  }

  // A tiny compute kernel: sum of squares 1..10 = 385
  uint32_t acc = 0;
  for (uint32_t i = 1; i <= 10; i++) acc += i * i;
  SCRATCH = acc;

  // "Knight rider" on the 8 LEDs, speed selected by gpio_in[1:0]
  uint32_t speed = 1000u << (GPIO_IN & 0x3);
  for (int pass = 0; pass < 2; pass++) {
    for (int b = 0; b < 8; b++) { GPIO_OUT = 1u << b; delay(speed); }
    for (int b = 7; b >= 0; b--) { GPIO_OUT = 1u << b; delay(speed); }
  }

  GPIO_OUT = acc & 0xFF;  // final value 0x81 (385 & 0xFF)
  return 0;               // crt0 halts the core -> 'halted' pad goes high
}
