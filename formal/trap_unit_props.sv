// Properties of trap_unit (combinational), checked on the Verilog netlist GHDL synthesizes.
module props (input clk);
  (* anyseq *) wire ex_valid, run, cf_taken, csr_illegal, illegal;
  (* anyseq *) wire [6:0] opcode;
  (* anyseq *) wire [2:0] funct3;
  (* anyseq *) wire [4:0] rd_idx, rs1_idx;
  (* anyseq *) wire [11:0] imm12;
  (* anyseq *) wire [31:0] ea, cf_target;
  (* anyseq *) wire irq_take;
  (* anyseq *) wire [31:0] irq_cause;
  wire take, mret_take, irq; wire [31:0] cause, tval;

  trap_unit dut (.i_ex_valid(ex_valid), .i_run(run), .i_opcode(opcode), .i_funct3(funct3), .i_rd_idx(rd_idx),
    .i_rs1_idx(rs1_idx), .i_imm12(imm12), .i_ea(ea), .i_cf_taken(cf_taken), .i_cf_target(cf_target),
    .i_csr_illegal(csr_illegal), .i_illegal(illegal), .i_irq_take(irq_take), .i_irq_cause(irq_cause),
    .o_take(take), .o_mret_take(mret_take), .o_irq(irq), .o_cause(cause), .o_tval(tval));

  localparam SYSTEM = 7'b1110011, LOAD = 7'b0000011, STORE = 7'b0100011;
  wire no_regs = funct3 == 3'b000 && rd_idx == 5'd0 && rs1_idx == 5'd0;
  wire cf_misal = cf_taken && cf_target[1:0] != 2'b00;
  wire active = ex_valid && run;
  wire fence_i = opcode == 7'b0001111 && funct3 == 3'b001;
  // An interrupt is taken on the instruction in EX when it is valid, advancing and not a FENCE.I.
  wire irq_go = irq_take && active && !fence_i;

`ifndef IRQ
  // Without the interrupt proof the unit has no interrupt to take: the synchronous behaviour stands alone.
  always @(*) assume (!irq_take);
`endif

  // Only a branch, JAL or JALR is a taken control-flow instruction.
  // The decoder never flags SYSTEM: the trap unit decides it.
  always @(*) assume (!illegal || opcode != SYSTEM);

  always @(*) assume (!cf_taken || opcode == 7'b1100011 || opcode == 7'b1101111 || opcode == 7'b1100111);

`ifdef IRQ
  // The interrupt: it is taken exactly when there is one to take on a valid, advancing instruction that is not a
  // FENCE.I; it carries the cause it was given, an mtval of zero, no MRET and the interrupt flag.
  always @(*) begin
    assert (irq == irq_go);
    if (irq_go) assert (take && !mret_take && cause == irq_cause && tval == 32'h0);
    if (!irq_go) assert (!irq);
    // MRET is aborted by an interrupt and executed without one.
    if (active && opcode == SYSTEM && no_regs && imm12 == 12'h302) assert (mret_take == !irq_go);
    // FENCE.I redirects the pipeline, so it is never aborted by an interrupt, and it raises nothing by itself.
    if (fence_i) assert (!irq);
    if (fence_i && active && !illegal && !cf_misal) assert (!take);
  end
`endif

  always @(*) if (!irq_go) begin
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
      if (cause == 2) assert (illegal || opcode == SYSTEM);
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

    // A flagged instruction traps with cause 2, unless its jump target is misaligned.
    if (active && illegal && !cf_misal) assert (take && cause == 2);

    // Aligned accesses and aligned jumps do not trap.

    if (opcode == LOAD && !cf_misal && !illegal && ((funct3 == 3'b010 && ea[1:0] == 0) || (funct3[1:0] == 2'b01 && !ea[0]) || funct3[1:0] == 2'b00 || funct3 == 3'b100))
      assert (!take);
    if (opcode == STORE && !cf_misal && !illegal && ((funct3 == 3'b010 && ea[1:0] == 0) || (funct3 == 3'b001 && !ea[0]) || funct3 == 3'b000))
      assert (!take);
    if (opcode != SYSTEM && opcode != LOAD && opcode != STORE && !cf_misal && !illegal) assert (!take);
  end

`ifdef ZICCLSM_ON
  // With Zicclsm the main memory (RAM and SDRAM, [0x8000, 0x80000000)) runs a misaligned access when its two words
  // lie in the same region, and everything else traps with cause 4 or 6.
  wire is_load  = opcode == LOAD  && (funct3 == 3'b010 || funct3[1:0] == 2'b01 || funct3[1:0] == 2'b00 || funct3 == 3'b100);
  wire is_store = opcode == STORE && (funct3 == 3'b010 || funct3 == 3'b001 || funct3 == 3'b000);
  wire unaligned = ((funct3 == 3'b010 && ea[1:0] != 0) || (funct3[1:0] == 2'b01 && ea[0]));
  wire [31:0] next_word = {ea[31:2] + 30'd1, 2'b00};
`ifdef EXT_FLASH
  // Memory map of the sdram platform: the flash is [0x20000000, 0x40000000) and the SDRAM [0x40000000, 0x60000000).
  wire ram_pair  = ea >= 32'h20000000 && ea < 32'h40000000 && next_word >= 32'h20000000 && next_word < 32'h40000000;
  wire sdram_pair = ea >= 32'h40000000 && ea < 32'h60000000 && next_word >= 32'h40000000 && next_word < 32'h60000000;
  wire crosses  = (funct3 == 3'b010 && ea[1:0] != 0) || (funct3[1:0] == 2'b01 && ea[1:0] == 2'b11);
  wire in_word  = funct3[1:0] == 2'b01 && ea[1:0] == 2'b01 && ea >= 32'h20000000 && ea < 32'h60000000;
`else
  wire ram_pair  = ea >= 32'h8000 && ea < 32'h40000000 && next_word >= 32'h8000 && next_word < 32'h40000000;
  wire sdram_pair = ea >= 32'h40000000 && ea < 32'h80000000 && next_word >= 32'h40000000 && next_word < 32'h80000000;
  wire crosses  = (funct3 == 3'b010 && ea[1:0] != 0) || (funct3[1:0] == 2'b01 && ea[1:0] == 2'b11);
  wire in_word  = funct3[1:0] == 2'b01 && ea[1:0] == 2'b01 && ea >= 32'h8000 && ea < 32'h80000000;
`endif
  wire runs     = in_word || (crosses && (ram_pair || sdram_pair));
  always @(*) begin
    if (active && !cf_misal && !illegal && (is_load || is_store) && unaligned && runs) assert (!take);
    if (active && !cf_misal && !illegal && is_load  && unaligned && !runs) assert (take && cause == 4 && tval == ea);
    if (active && !cf_misal && !illegal && is_store && unaligned && !runs) assert (take && cause == 6 && tval == ea);
  end
`endif

`ifdef ZICCLSM_OFF
  // Without Zicclsm every misaligned load and store traps.
  wire unaligned = ((funct3 == 3'b010 && ea[1:0] != 0) || (funct3[1:0] == 2'b01 && ea[0]));
  always @(*) begin
    if (active && !cf_misal && !illegal && opcode == LOAD  && (funct3 == 3'b010 || funct3[1:0] == 2'b01) && unaligned)
      assert (take && cause == 4 && tval == ea);
    if (active && !cf_misal && !illegal && opcode == STORE && (funct3 == 3'b010 || funct3 == 3'b001) && unaligned)
      assert (take && cause == 6 && tval == ea);
  end
`endif

`ifdef CHECK_EA_OFF
  // The instance that does not know the effective address (the EX stage of a core that checks it in MEM) never
  // raises a load or store address exception.
  always @(*) assert (!(take && (cause == 4 || cause == 6)));
`endif

`ifdef COVER
  always @(*) begin
    cover (take && cause == 0);
    cover (take && cause == 2 && illegal);
    cover (take && cause == 2 && opcode == SYSTEM && funct3 == 3'b001);
    cover (take && cause == 2 && opcode == SYSTEM && funct3 == 3'b000);
    cover (take && cause == 3);
    cover (take && cause == 4);
    cover (take && cause == 6);
    cover (take && cause == 11);
    cover (mret_take);
`ifdef IRQ
    cover (irq && opcode == SYSTEM && no_regs && imm12 == 12'h000);
    cover (irq && opcode == SYSTEM && no_regs && imm12 == 12'h302);
    cover (irq && illegal);
    cover (irq && cf_misal);
    cover (irq && opcode == LOAD);
    cover (irq_take && active && fence_i);
`endif
  end
`endif
endmodule
