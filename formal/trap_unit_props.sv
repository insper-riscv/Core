// Properties of trap_unit (combinational), checked on the Verilog netlist GHDL synthesizes.
module props (input clk);
  (* anyseq *) wire ex_valid, run, cf_taken, csr_illegal;
  (* anyseq *) wire [6:0] opcode;
  (* anyseq *) wire [2:0] funct3;
  (* anyseq *) wire [4:0] rd_idx, rs1_idx;
  (* anyseq *) wire [11:0] imm12;
  (* anyseq *) wire [31:0] ea, cf_target;
  wire take, mret_take; wire [31:0] cause, tval;

  trap_unit dut (.ex_valid(ex_valid), .run(run), .opcode(opcode), .funct3(funct3), .rd_idx(rd_idx),
    .rs1_idx(rs1_idx), .imm12(imm12), .ea(ea), .cf_taken(cf_taken), .cf_target(cf_target),
    .csr_illegal(csr_illegal), .take(take), .mret_take(mret_take), .cause(cause), .tval(tval));

  localparam SYSTEM = 7'b1110011, LOAD = 7'b0000011, STORE = 7'b0100011;
  wire no_regs = funct3 == 3'b000 && rd_idx == 5'd0 && rs1_idx == 5'd0;
  wire cf_misal = cf_taken && cf_target[1:0] != 2'b00;
  wire active = ex_valid && run;

  // Only a branch, JAL or JALR is a taken control-flow instruction.
  always @(*) assume (!cf_taken || opcode == 7'b1100011 || opcode == 7'b1101111 || opcode == 7'b1100111);

  always @(*) begin
    // An instruction that is not valid, or a pipeline that does not run, takes nothing.
    assert (!take || active);
    assert (!mret_take || active);
    assert (!(take && mret_take));

    // MRET is exactly 0x30200073.
    assert (!mret_take || (opcode == SYSTEM && no_regs && imm12 == 12'h302));
    if (active && opcode == SYSTEM && no_regs && imm12 == 12'h302) assert (mret_take && !take);

    // The causes, and what mtval carries for each.
    if (take) begin
      assert (cause == 0 || cause == 2 || cause == 3 || cause == 4 || cause == 6 || cause == 11);
      if (cause == 2 || cause == 3 || cause == 11) assert (tval == 32'h0);
      if (cause == 4 || cause == 6) assert (tval == ea);
      if (cause == 0) assert (cf_misal && tval == cf_target);
      if (cause == 4) assert (opcode == LOAD);
      if (cause == 6) assert (opcode == STORE);
      if (cause == 3) assert (opcode == SYSTEM && no_regs && imm12 == 12'h001);
      if (cause == 11) assert (opcode == SYSTEM && no_regs && imm12 == 12'h000);
    end

    // ecall and ebreak always trap; wfi never does.
    if (active && opcode == SYSTEM && no_regs && imm12 == 12'h000) assert (take && cause == 11);
    if (active && opcode == SYSTEM && no_regs && imm12 == 12'h001 && !cf_misal) assert (take && cause == 3);
    if (active && opcode == SYSTEM && no_regs && imm12 == 12'h105) assert (!take && !mret_take);

    // Aligned accesses and aligned jumps do not trap.
    if (opcode == LOAD && !cf_misal && ((funct3 == 3'b010 && ea[1:0] == 0) || (funct3[1:0] == 2'b01 && !ea[0]) || funct3[1:0] == 2'b00 || funct3 == 3'b100))
      assert (!take);
    if (opcode == STORE && !cf_misal && ((funct3 == 3'b010 && ea[1:0] == 0) || (funct3 == 3'b001 && !ea[0]) || funct3 == 3'b000))
      assert (!take);
    if (opcode != SYSTEM && opcode != LOAD && opcode != STORE && !cf_misal) assert (!take);
  end

`ifdef COVER
  always @(*) begin
    cover (take && cause == 0);
    cover (take && cause == 2 && opcode == SYSTEM && funct3 == 3'b001);
    cover (take && cause == 2 && opcode == SYSTEM && funct3 == 3'b000);
    cover (take && cause == 3);
    cover (take && cause == 4);
    cover (take && cause == 6);
    cover (take && cause == 11);
    cover (mret_take);
  end
`endif
endmodule
