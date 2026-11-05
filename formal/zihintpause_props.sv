// Properties of zihintpause_decode (combinational), checked on the Verilog netlist GHDL synthesizes.
module props (input clk);
  (* anyseq *) wire [31:0] instr;
  wire is_hint;

  zihintpause_decode dut (.i_instr(instr), .o_is_hint(is_hint));

  // The manual's encoding (Zihintpause 2.0): FENCE with fm = 0000, pred = 0001, succ = 0000, rs1 = rd = x0.
  wire pause = instr == 32'h0100000F;

  always @(*) begin
    // The decoder claims exactly that word.
    assert (is_hint == pause);
`ifdef COVER
    cover (pause);
    cover (instr[6:0] == 7'b0001111 && instr[14:12] == 3'b000 && !pause);
`endif
  end
endmodule
