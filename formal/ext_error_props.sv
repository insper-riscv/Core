// Properties of the access fault by external error of stage_mem, checked on the Verilog netlist GHDL synthesizes
// (stage_mem with the address check on and the classification registered, the way the core instantiates it), with
// the default map of the config_pkg and has_access_faults on. The external port answers a transaction with ready and,
// when no slave takes the address, with error. Whatever the access is:
//  1. an access of a load or a store valid in MEM that leaves by the external port and ends with ready and error,
//     and that no earlier exception stopped, takes the exception in the same cycle with cause 5 (load) or 7 (store)
//     and mtval = effective address;
//  2. the exception is precise: the access was issued exactly once to the external port (read or write strobe), and
//     no other memory (BOOT_MEMORY, FLASH, RAM) sees it;
//  3. the error never raises the exception without ready, on an access that does not use the external port, on an
//     instruction that is not valid, or on a bubble, and cause 5 comes only from the error;
//  4. an access that ends with ready and no error takes no exception, and the pipeline waits (o_ext_wait) while the
//     slave does not answer.
// With -DNO_FAULTS (has_access_faults off) the error is ignored and the stage never raises cause 5.
module props (input clk);
  (* anyseq *) wire valid, ready, error, flag_flash, flag_sdram, flag_main, flag_same, flag_ok_wr;
  (* anyseq *) wire we_ram, re_ram;
  (* anyseq *) wire [2:0] funct3;
  (* anyseq *) wire [3:0] byte_mask;
  (* anyseq *) wire [31:0] ea, alu_out, store_data;
  wire en_ram = we_ram || re_ram;
  wire flash_en, ram_en, ram_wr, ram_rd, ext_rd, ext_wr, ext_wait, take;
  wire [31:0] cause, tval, ram_addr, ram_wdata, ext_addr, ext_wdata, flash_addr;
  wire [3:0] ram_be, ext_be;

  stage_mem dut (
    .i_valid(valid), .i_alu_out(alu_out), .i_ea(ea), .i_flag_flash(flag_flash), .i_flag_sdram(flag_sdram),
    .i_flag_main(flag_main), .i_flag_same(flag_same), .i_flag_ok_wr(flag_ok_wr), .i_funct3(funct3),
    .i_store_data(store_data), .i_byte_mask(byte_mask), .i_we_ram(we_ram), .i_re_ram(re_ram), .i_en_ram(en_ram),
    .i_ext_ready(ready), .i_ext_error(error), .o_flash_addr2(flash_addr), .o_flash_rden2(flash_en),
    .o_ram_addr(ram_addr), .o_ram_wdata(ram_wdata), .o_ram_en(ram_en), .o_ram_wren(ram_wr), .o_ram_rden(ram_rd),
    .o_ram_byteena(ram_be), .o_ext_addr(ext_addr), .o_ext_wdata(ext_wdata), .o_ext_byteena(ext_be),
    .o_ext_rden(ext_rd), .o_ext_wren(ext_wr), .o_ext_wait(ext_wait), .o_trap_take(take), .o_trap_cause(cause),
    .o_trap_tval(tval));

  // A load or store never is both, and the classification is one of the three paths.
  always @(*) assume (!(we_ram && re_ram));
  always @(*) assume (flag_flash + flag_sdram <= 1);
  // Only the word-aligned and byte accesses reach the memory without the address exception, so the fault proof looks at
  // them (the address exception has its own proofs).
  wire aligned = funct3 == 3'b000 || funct3 == 3'b100 || (funct3 == 3'b010 && ea[1:0] == 2'b00);
  wire ext_access = valid && en_ram && flag_sdram;
  // The stores the map refuses (flag_ok_wr low) trap before they reach the port.
  wire pre_trap = we_ram && !flag_ok_wr;
  wire fault = ext_access && ready && error && aligned && !pre_trap;

`ifdef NO_FAULTS
  always @(*) begin
    assert (!(take && cause == 5));
    assert (!(take && cause == 7 && (flag_ok_wr || !we_ram)));
  end
`else
  always @(*) begin
    // 1. The error ends the access with the fault of the access type, carrying the effective address.
    if (fault && re_ram) assert (take && cause == 5 && tval == ea);
    if (fault && we_ram) assert (take && cause == 7 && tval == ea);
    // 2. The access was issued once to the external port, and to no other memory.
    if (fault && re_ram) assert (ext_rd && !ext_wr && !ram_rd && !ram_wr && !flash_en);
    if (fault && we_ram) assert (ext_wr && !ext_rd && !ram_rd && !ram_wr && !flash_en);
    if (fault) assert (!ext_wait);
    // 3. The fault is only the error of an external access that completed.
    if (take && cause == 5) assert (valid && re_ram && flag_sdram && ready && error);
    if (take && cause == 7 && flag_ok_wr) assert (valid && we_ram && flag_sdram && ready && error);
    if (!valid) assert (!take);
    // 4. No error, no fault; no ready, no fault and the pipeline waits.
    if (ext_access && aligned && !pre_trap && ready && !error) assert (!take && !ext_wait);
    if (ext_access && aligned && !pre_trap && !ready) assert (!take && ext_wait);
    // An error on an access that does not use the external port is ignored.
    if (valid && en_ram && !flag_sdram && aligned && !pre_trap) assert (!take);
  end
`endif

`ifdef COVER
  always @(*) begin
    cover (fault && re_ram && take && cause == 5);
    cover (fault && we_ram && take && cause == 7);
    cover (ext_access && aligned && ready && !error && !take);
    cover (ext_access && aligned && !ready && ext_wait);
    cover (valid && en_ram && !flag_sdram && error && !take);
  end
`endif
endmodule
