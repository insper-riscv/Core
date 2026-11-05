// Properties of zihintntl_decode (combinational), checked on the Verilog netlist GHDL synthesizes.
module props (input clk);
  (* anyseq *) wire [31:0] instr;
  wire is_hint;

  zihintntl_decode dut (.i_instr(instr), .o_is_hint(is_hint));

  localparam OP = 7'b0110011;

  // The manual's encodings (Zihintntl 1.0): ADD with rd = rs1 = x0 and rs2 = x2, x3, x4 or x5.
  wire ntl = instr[6:0] == OP && instr[14:12] == 3'b000 && instr[31:25] == 7'b0000000 &&
             instr[11:7] == 5'd0 && instr[19:15] == 5'd0 && instr[24:20] >= 5'd2 && instr[24:20] <= 5'd5;

  always @(*) begin
    // The decoder claims exactly the four encodings.
    assert (is_hint == ntl);
`ifdef COVER
    cover (ntl);
    cover (instr[6:0] == OP && instr[11:7] == 5'd0 && instr[19:15] == 5'd0 && !ntl);
    cover (instr[6:0] == OP && instr[11:7] != 5'd0 && instr[24:20] == 5'd2 && !ntl);
`endif
  end
endmodule
