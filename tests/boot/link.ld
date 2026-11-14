/* Mapa mínimo do Spike: código em 0x80000000 e a região do tohost do HTIF. */
OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS
{
    . = 0x80000000;
    .text : { *(.text.init) *(.text*) }
    . = ALIGN(0x1000);
    .tohost : { *(.tohost) }
}
