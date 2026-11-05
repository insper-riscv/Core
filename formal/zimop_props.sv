// Properties of zimop_decode (combinational), checked on the Verilog netlist GHDL synthesizes.
module props (input clk);
  (* anyseq *) wire [31:0] instr;
  wire is_zimop, we_reg; wire [4:0] alu_op; wire [6:0] opcode_out;

  zimop_decode dut (.i_instr(instr), .o_is_zimop(is_zimop), .o_we_reg(we_reg), .o_alu_op(alu_op), .o_opcode(opcode_out));

  localparam SYSTEM = 7'b1110011, OP_IMM = 7'b0010011, BGEU = 5'b11111;

  // The manual's encodings (Zimop 1.0, chapter 9): SYSTEM with funct3 = 100 and
  //   mop.r.n  = 1 n[4] 0 0 n[3:2] 0 111 n[1:0] rs1 100 rd 1110011   (32 values of n)
  //   mop.rr.n = 1 n[2] 0 0 n[1:0] 1 rs2 rs1 100 rd 1110011         (8 values of n)
  wire mop_r  = instr[6:0] == SYSTEM && instr[14:12] == 3'b100 && instr[31] && instr[29:28] == 2'b00 &&
                !instr[25] && instr[24:22] == 3'b111;
  wire mop_rr = instr[6:0] == SYSTEM && instr[14:12] == 3'b100 && instr[31] && instr[29:28] == 2'b00 && instr[25];

  always @(*) begin
    // The decoder claims exactly the 40 encodings, whatever rd, rs1 and rs2 hold.
    assert (is_zimop == (mop_r || mop_rr));
    // A claimed instruction writes rd; every other one is left alone.
    assert (we_reg == is_zimop);
    // The ALU operation has no data result, so the value written is zero, and the next stages see an ordinary
    // arithmetic opcode instead of SYSTEM, so no illegal-instruction exception follows.
    assert (alu_op == BGEU);
    assert (opcode_out == OP_IMM);
`ifdef COVER
    cover (mop_r);
    cover (mop_rr);
    cover (instr[6:0] == SYSTEM && !is_zimop);
`endif
  end
endmodule
