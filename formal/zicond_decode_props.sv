// Properties of zicond_decode (combinational), checked on the Verilog netlist GHDL synthesizes.
// The decoder claims exactly the two R-type encodings of Zicond 1.0.0 (opcode 0110011, funct7 0000111, funct3
// 101 for czero.eqz and 111 for czero.nez), whatever the register fields, and hands the EX stage the operation
// code that zicond_unit decodes.
module props (input clk);
  (* anyseq *) wire [31:0] instr;
  wire is_zicond, we_reg, sel_pc_rs1; wire [4:0] alu_op;

  zicond_decode dut (.i_instr(instr), .o_is_zicond(is_zicond), .o_alu_op(alu_op), .o_we_reg(we_reg),
    .o_sel_pc_rs1(sel_pc_rs1));

  wire [6:0] opcode = instr[6:0], funct7 = instr[31:25];
  wire [2:0] funct3 = instr[14:12];
  wire is_eqz = opcode == 7'b0110011 && funct7 == 7'b0000111 && funct3 == 3'b101;
  wire is_nez = opcode == 7'b0110011 && funct7 == 7'b0000111 && funct3 == 3'b111;

  always @(*) begin
    // 1. The claim is exactly the two encodings.
    assert (is_zicond == (is_eqz || is_nez));
    // 2. The operation code names the instruction.
    if (is_eqz) assert (alu_op == 5'b01100);
    if (is_nez) assert (alu_op == 5'b01110);
    if (!is_zicond) assert (alu_op == 5'b00000);
    // 3. A claimed instruction writes rd and reads rs1; an unclaimed one does neither here.
    assert (we_reg == is_zicond && sel_pc_rs1 == is_zicond);
  end

`ifdef COVER
  always @(*) begin
    cover (is_eqz);
    cover (is_nez);
    cover (opcode == 7'b0110011 && funct7 == 7'b0000111 && funct3 == 3'b100);
    cover (opcode == 7'b0110011 && funct7 == 7'b0000110 && funct3 == 3'b101);
  end
`endif
endmodule
