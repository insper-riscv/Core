// Properties of o_trap_take in the core with Zicsr, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// Whatever the memories and the instructions answer, the core handles every exception at mtvec, so o_trap stays low,
// and the cycle in which it takes an exception retires nothing: the instruction that raised it does not count
// and no instruction is retired on top of it. Two takes never come in consecutive cycles, because the pipeline is
// flushed by the first. The cover shows that a take is reachable.
module props (input clk);
  (* anyseq *) wire reset, sdram_ready, ic_ready, dc_done, irq_software, irq_timer, irq_external;
  (* anyseq *) wire [31:0] boot_rom_data, flash_data, flash_data2, ram_rdata, sdram_rdata, ic_data;
  (* anyseq *) wire [2:0] hpm_ext_events;
  wire [31:0] if_addr, flash_addr2, ram_addr, ram_wdata, sdram_addr, sdram_wdata, trap_cause, trap_pc;
  wire [3:0] ram_byteena, sdram_byteena;
  wire if_rden, flash_rden2, ram_en, ram_wren, ram_rden, sdram_rden, sdram_wren, mem_advance, ic_sel, ic_inval;
  wire dc_flush, trap, trap_take, retire;

  core dut (.i_clk(clk), .i_rst(reset), .o_if_addr(if_addr), .o_if_rden(if_rden), .i_boot_rom_data(boot_rom_data),
    .i_flash_data(flash_data), .o_flash_addr2(flash_addr2), .o_flash_rden2(flash_rden2), .i_flash_data2(flash_data2),
    .o_ram_addr(ram_addr), .o_ram_wdata(ram_wdata), .i_ram_rdata(ram_rdata), .o_ram_en(ram_en), .o_ram_wren(ram_wren),
    .o_ram_rden(ram_rden), .o_ram_byteena(ram_byteena), .o_sdram_addr(sdram_addr), .o_sdram_wdata(sdram_wdata),
    .o_sdram_byteena(sdram_byteena), .o_sdram_rden(sdram_rden), .o_sdram_wren(sdram_wren), .i_sdram_rdata(sdram_rdata),
    .i_sdram_ready(sdram_ready), .o_mem_advance(mem_advance), .i_ic_data(ic_data), .i_ic_ready(ic_ready),
    .o_ic_sel(ic_sel), .o_ic_inval(ic_inval), .o_dc_flush(dc_flush), .i_dc_done(dc_done), .o_trap(trap),
    .o_trap_cause(trap_cause), .o_trap_pc(trap_pc), .o_trap_take(trap_take), .o_retire(retire),
    .i_hpm_ext_events(hpm_ext_events), .i_irq_software(irq_software), .i_irq_timer(irq_timer),
    .i_irq_external(irq_external));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);

  reg p_take = 0;
  always @(posedge clk) p_take <= trap_take;

  always @(*) begin
`ifdef COVER
    cover (trap_take);
`else
    assert (!trap);
    assert (!(trap_take && retire));
`endif
  end

`ifndef COVER
  always @(posedge clk) assert (!(trap_take && p_take));
`endif
endmodule
