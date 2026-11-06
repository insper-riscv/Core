// Properties of the interrupt entry in stage_ex (has_zicsr and has_interrupts on), checked on the Verilog netlist
// GHDL synthesizes. The stage is the one that decides the entry: it joins the trap unit, the CSR bank and the
// choice of the next PC, so what is proven here is what the program sees after an interrupt aborts the
// instruction in EX at cycle t (the aborted instruction is a plain ADDI, or a CSR access to mscratch, mie or
// mtvec, which can raise nothing by itself, so a trap taken on it is an interrupt):
//  1. mepc reads the address of the aborted instruction, so MRET runs that very instruction (it is the first
//     one that did not complete);
//  2. mcause reads 0x80000003, 0x80000007 or 0x8000000B, and the line of that cause was high at cycle t;
//  3. mstatus reads MIE = 0 and MPIE = 1 (the interrupt was taken with MIE = 1);
//  4. the next PC of cycle t is BASE in the direct mode, and BASE with bits 5:2 replaced by the cause code (3, 7 or
//     11) in the vectored mode;
//  5. an aborted CSR access leaves the CSR it addressed as it was: the read of cycle t + 1 equals the read of t;
//  6. an ECALL with no line high traps with cause 11 to BASE, whatever the mode of mtvec (the vector is only for
//     interrupts).
// Cycle t + 1 is a CSR read (CSRRS with rs1 = x0) of the address the property asks about; no other
// instruction is constrained. The properties depend only on the state at t, so they are proven by induction.
module props (input clk);
  (* anyseq *) wire reset, base_run, pipe_run, valid, valid_raw, retire, sel_pc4_alu, sel_rs2_imm, sel_pc_rs1;
  (* anyseq *) wire is_muldiv, is_csr, illegal, irq_sw, irq_tm, irq_ex, dc_done, exmem_ok, memwb_ok, wb2_ok;
  (* anyseq *) wire [31:0] pc, pc4, rs1_val, rs2_val, imm, exmem_alu_out, memwb_alu_out, wb2_data;
  (* anyseq *) wire [4:0] rs1_idx, rd_idx, alu_op;
  (* anyseq *) wire [7:0] alu_sel;
  (* anyseq *) wire [6:0] opcode;
  (* anyseq *) wire [2:0] funct3, fwd1, fwd2;
  wire [31:0] final_result, store_data, branch_target, jalr_target, redirect_pc, sig_cause, sig_pc;
  wire [3:0] store_mask;
  wire branch_taken, jalr_taken, trap_take, trap_sig, mret_take, fencei_take, fencei_inval, fencei_busy, dc_flush;
  wire muldiv_stall, muldiv_fused;

  stage_ex dut (
    .i_hpm_events(16'h0), .i_irq_software(irq_sw), .i_irq_timer(irq_tm), .i_irq_external(irq_ex),
    .i_clk(clk), .i_rst(reset), .i_base_run(base_run), .i_pipe_run(pipe_run), .i_valid(valid), .i_retire(retire),
    .i_pc(pc), .i_pc4(pc4), .i_rs1_idx(rs1_idx), .i_rd_idx(rd_idx), .i_rs1_val(rs1_val), .i_rs2_val(rs2_val),
    .i_imm(imm), .i_sel_pc4_alu(sel_pc4_alu), .i_sel_rs2_imm(sel_rs2_imm), .i_sel_pc_rs1(sel_pc_rs1),
    .i_alu_op(alu_op), .i_alu_sel(alu_sel), .i_is_muldiv(is_muldiv), .i_is_csr(is_csr), .i_illegal(illegal),
    .i_opcode(opcode), .i_funct3(funct3), .i_fwd_match_rs1(fwd1), .i_fwd_match_rs2(fwd2),
    .i_exmem_ok(exmem_ok), .i_memwb_ok(memwb_ok), .i_wb2_ok(wb2_ok), .i_exmem_alu_out(exmem_alu_out),
    .i_memwb_alu_out(memwb_alu_out), .i_wb2_data(wb2_data), .i_dc_done(dc_done), .i_valid_raw(valid_raw),
    .i_mem_trap_take(1'b0), .i_mem_trap_cause(32'h0), .i_mem_trap_pc(32'h0), .i_mem_trap_tval(32'h0),
    .o_final_result(final_result), .o_store_data(store_data), .o_store_byte_mask(store_mask),
    .o_branch_taken(branch_taken), .o_jalr_taken(jalr_taken), .o_branch_target(branch_target),
    .o_jalr_target(jalr_target), .o_redirect_pc(redirect_pc), .o_trap_take(trap_take), .o_trap_sig(trap_sig),
    .o_trap_sig_cause(sig_cause), .o_trap_sig_pc(sig_pc), .o_mret_take(mret_take), .o_fencei_take(fencei_take),
    .o_fencei_inval(fencei_inval), .o_fencei_busy(fencei_busy), .o_dc_flush(dc_flush),
    .o_muldiv_stall(muldiv_stall), .o_muldiv_fused(muldiv_fused));

  localparam [6:0] SYSTEM = 7'b1110011, OP_IMM = 7'b0010011;

  reg f_past = 0;
  initial assume (reset);
  always @(*) if (f_past) assume (!reset);
  // The pipeline advances only when EX and MEM are free, and the core has no multiplier here.
  always @(*) assume (!pipe_run || base_run);
  always @(*) assume (!is_muldiv);

  // What the previous cycle (t) was.
  reg p_reset = 1, p_take = 0, p_irq_sw = 0, p_irq_tm = 0, p_irq_ex = 0;
  reg p_plain = 0, p_csrw = 0, p_ecall = 0;
  reg [31:0] p_pc = 0, p_redirect = 0, p_final = 0;
  reg [11:0] p_addr = 0;

  wire csr_op = is_csr && opcode == SYSTEM && funct3 != 3'b000 && funct3 != 3'b100;
  wire csr_target = imm[11:0] == 12'h340 || imm[11:0] == 12'h304 || imm[11:0] == 12'h305;
  wire plain_now = valid && pipe_run && opcode == OP_IMM && !is_csr && !illegal && !sel_pc4_alu;
  wire csrw_now = valid && pipe_run && csr_op && csr_target && !illegal && !sel_pc4_alu;

  wire ecall_now = valid && pipe_run && opcode == SYSTEM && funct3 == 3'b000 && rd_idx == 5'd0 &&
                   rs1_idx == 5'd0 && imm[11:0] == 12'h000 && !illegal && !is_csr && !sel_pc4_alu;
  // An ECALL is looked at with every line low, so that the trap it takes is its own.
  always @(*) if (ecall_now) assume (!irq_sw && !irq_tm && !irq_ex);

  always @(posedge clk) begin
    f_past <= 1;
    p_reset <= reset;
    p_ecall <= ecall_now;
    p_take <= trap_take;
    p_irq_sw <= irq_sw; p_irq_tm <= irq_tm; p_irq_ex <= irq_ex;
    p_plain <= plain_now;
    p_csrw <= csrw_now;
    p_pc <= pc; p_redirect <= redirect_pc; p_final <= final_result; p_addr <= imm[11:0];
  end

  // The registers clear while reset is high, so a trap seen in a reset cycle changes nothing.
  wire live = f_past && !p_reset;
  wire after_plain = live && p_take && p_plain;
  wire after_csrw = live && p_take && p_csrw;
  wire after_ecall = live && p_take && p_ecall;

  // Cycle t + 1 reads a CSR: the one the aborted access addressed, or one of the four the properties ask about.
  wire read_form = valid && pipe_run && base_run && is_csr && opcode == SYSTEM && funct3 == 3'b010 &&
                   rs1_idx == 5'd0 && !illegal && !sel_pc4_alu;
  wire read_asked = imm[11:0] == 12'h341 || imm[11:0] == 12'h342 || imm[11:0] == 12'h300 || imm[11:0] == 12'h305;
  always @(*) begin
    if (after_plain) assume (read_form && read_asked);
    if (after_csrw) assume (read_form && imm[11:0] == p_addr);
    if (after_ecall) assume (read_form && (imm[11:0] == 12'h305 || imm[11:0] == 12'h342));
  end

  wire [3:0] code = final_result[3:0];

  always @(*) if (f_past && !reset) begin
    if (after_plain && imm[11:0] == 12'h341) assert (final_result == {p_pc[31:2], 2'b00});
    if (after_plain && imm[11:0] == 12'h342) begin
      assert (final_result[31] && final_result[30:4] == 27'h0);
      assert (code == 4'd3 || code == 4'd7 || code == 4'd11);
      if (code == 4'd3) assert (p_irq_sw);
      if (code == 4'd7) assert (p_irq_tm);
      if (code == 4'd11) assert (p_irq_ex);
    end
    if (after_plain && imm[11:0] == 12'h300) assert (!final_result[3] && final_result[7]);
    if (after_plain && imm[11:0] == 12'h305) begin
      if (!final_result[0]) assert (p_redirect == {final_result[31:2], 2'b00});
      if (final_result[0]) begin
        assert (p_redirect[31:6] == final_result[31:6] && p_redirect[1:0] == 2'b00);
        assert (p_redirect[5:2] == 4'd3 || p_redirect[5:2] == 4'd7 || p_redirect[5:2] == 4'd11);
      end
    end
    if (after_csrw) assert (final_result == p_final);
    if (after_ecall && imm[11:0] == 12'h305) assert (p_redirect == {final_result[31:2], 2'b00});
    if (after_ecall && imm[11:0] == 12'h342) assert (final_result == 32'd11);
  end

`ifdef COVER
  always @(*) if (f_past && !reset) begin
    cover (after_plain && imm[11:0] == 12'h341);
    cover (after_plain && imm[11:0] == 12'h342 && code == 4'd11);
    cover (after_plain && imm[11:0] == 12'h305 && final_result[0]);
    cover (after_csrw && p_addr == 12'h304);
    cover (after_csrw && p_addr == 12'h305);
    cover (after_csrw && p_addr == 12'h340);
    cover (after_ecall && imm[11:0] == 12'h305 && final_result[0]);
    cover (after_ecall && imm[11:0] == 12'h342);
  end
`endif
endmodule
