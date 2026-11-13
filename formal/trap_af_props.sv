// Properties of the access faults of trap_unit (has_access_faults on), checked on the Verilog netlist GHDL
// synthesizes from the VHDL. Two flags come from the memory map: the fetch of the instruction is from an
// executable region (fetch_ok) and the effective address accepts a write (wr_ok). The load fault (cause 5) does not
// come from this unit: it is the error answer of the external port, raised in the MEM stage (stage_mem), so here a
// load never faults. With the address check on (the default), whatever the instruction is (Table 17 of the privileged
// volume):
//  1. a valid, advancing instruction fetched from outside an executable region traps with cause 1 and mtval = PC,
//     whatever else it is (an illegal instruction, a misaligned jump, an ecall);
//  2. otherwise, an illegal instruction is cause 2, and a legal store the map refuses to write (the BOOT_MEMORY and
//     the FLASH) is cause 7 with mtval = effective address, unless the access is a misaligned one the hardware does
//     not execute (BOOT_MEMORY or direct FLASH), which keeps cause 6 (the optional order of Table 17);
//  3. cause 1 and 7 never occur for any other reason, cause 5 never occurs, and an instruction that is not valid or
//     does not advance takes nothing;
//  4. a load or store the map accepts keeps the behaviour of the unit without faults (aligned accesses do not trap).
module props (input clk);
  (* anyseq *) wire ex_valid, run, cf_taken, csr_illegal, illegal, fetch_ok, wr_ok;
  (* anyseq *) wire [6:0] opcode;
  (* anyseq *) wire [2:0] funct3;
  (* anyseq *) wire [4:0] rd_idx, rs1_idx;
  (* anyseq *) wire [11:0] imm12;
  (* anyseq *) wire [31:0] ea, cf_target, pc;
  wire take, mret_take, irq; wire [31:0] cause, tval;

  trap_unit dut (.i_ex_valid(ex_valid), .i_run(run), .i_opcode(opcode), .i_funct3(funct3), .i_rd_idx(rd_idx),
    .i_rs1_idx(rs1_idx), .i_imm12(imm12), .i_ea(ea), .i_cf_taken(cf_taken), .i_cf_target(cf_target),
    .i_csr_illegal(csr_illegal), .i_illegal(illegal), .i_fetch_ok(fetch_ok), .i_pc(pc),
    .i_ea_wr_ok(wr_ok), .i_irq_take(1'b0), .i_irq_cause(32'h0), .o_take(take), .o_mret_take(mret_take), .o_irq(irq), .o_cause(cause), .o_tval(tval));

  localparam SYSTEM = 7'b1110011, LOAD = 7'b0000011, STORE = 7'b0100011;
  wire active = ex_valid && run;
  wire is_ld = opcode == LOAD, is_st = opcode == STORE;
  always @(*) assume (!illegal || opcode != SYSTEM);
  always @(*) assume (!cf_taken || opcode == 7'b1100011 || opcode == 7'b1101111 || opcode == 7'b1100111);

  always @(*) begin
    if (active && !fetch_ok) assert (take && cause == 1 && tval == pc);
    if (active && fetch_ok && illegal) assert (take && cause == 2);
    if (active && fetch_ok && !illegal && is_st && !wr_ok && (funct3 == 3'b000 || (funct3 == 3'b010 && ea[1:0] == 0)))
      assert (take && cause == 7 && tval == ea);
    // A misaligned access outside the main memory (below 0x8000 here) is still cause 4 or 6, even when the map refuses it.
    if (active && fetch_ok && !illegal && is_st && !wr_ok && funct3 == 3'b010 && ea[1:0] != 0 && ea < 32'h8000) assert (take && cause == 6);
    if (take && cause == 1) assert (active && !fetch_ok);
    assert (!(take && cause == 5));
    if (take && cause == 7) assert (active && fetch_ok && !illegal && is_st && !wr_ok && tval == ea);
    if (!active) assert (!take);
    if (active && fetch_ok && !illegal && !cf_taken && is_ld && funct3 == 3'b010 && ea[1:0] == 0) assert (!take);
    if (active && fetch_ok && !illegal && !cf_taken && is_st && wr_ok && funct3 == 3'b010 && ea[1:0] == 0) assert (!take);
`ifdef COVER
    cover (take && cause == 1);
    cover (take && cause == 7);
    cover (take && cause == 1 && illegal);
    cover (take && cause == 6 && !wr_ok);
`endif
  end
endmodule
