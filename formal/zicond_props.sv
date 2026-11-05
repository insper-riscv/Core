// Properties of zicond_unit (combinational), checked on the Verilog netlist GHDL synthesizes.
// The model is Zicond 1.0.0 (chapter 10 of the unprivileged manual): czero.eqz gives zero when rs2 is zero and
// rs1 otherwise, czero.nez gives zero when rs2 is not zero and rs1 otherwise, and no other operation code is
// claimed. The operation codes are the ones the decoder hands to the EX stage.
module props (input clk);
  (* anyseq *) wire [4:0] op;
  (* anyseq *) wire [31:0] rs1, rs2;
  wire active; wire [31:0] result;

  zicond_unit dut (.i_op(op), .i_rs1(rs1), .i_rs2(rs2), .o_active(active), .o_result(result));

  localparam ALU_CZERO_EQZ = 5'b01100, ALU_CZERO_NEZ = 5'b01110;

  always @(*) begin
    // 1. czero.eqz: zero when rs2 is zero.
    if (op == ALU_CZERO_EQZ && rs2 == 32'h0) assert (active && result == 32'h0);
    // 2. czero.eqz: rs1 when rs2 is not zero.
    if (op == ALU_CZERO_EQZ && rs2 != 32'h0) assert (active && result == rs1);
    // 3. czero.nez: zero when rs2 is not zero.
    if (op == ALU_CZERO_NEZ && rs2 != 32'h0) assert (active && result == 32'h0);
    // 4. czero.nez: rs1 when rs2 is zero.
    if (op == ALU_CZERO_NEZ && rs2 == 32'h0) assert (active && result == rs1);
    // 5. Only the two operation codes of the extension are claimed.
    assert (active == (op == ALU_CZERO_EQZ || op == ALU_CZERO_NEZ));
    // 6. The result is never anything but zero or rs1.
    if (active) assert (result == 32'h0 || result == rs1);
  end

`ifdef COVER
  always @(*) begin
    cover (active && op == ALU_CZERO_EQZ && rs2 == 32'h0 && rs1 != 32'h0);
    cover (active && op == ALU_CZERO_EQZ && rs2 == 32'h80000000);
    cover (active && op == ALU_CZERO_NEZ && rs2 == 32'h0 && rs1 != 32'h0);
    cover (active && op == ALU_CZERO_NEZ && rs2 == 32'h1);
    cover (!active);
  end
`endif
endmodule
