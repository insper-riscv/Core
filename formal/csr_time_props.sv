// Properties of the CSR time with time_external (has_zicntr and time_external on), checked on the Verilog netlist
// GHDL synthesizes from the VHDL. The platform delivers mtime in a 64-bit port. Whatever the CSR instructions do:
//  1. a read of time (0xC01) gives the low half of mtime and a read of timeh (0xC81) the high half, in the same cycle;
//  2. a write to time or timeh is illegal, a read is not, and mcycle (0xB00) is not affected by mtime.
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [63:0] mtime;
  wire [31:0] rdata;
  wire illegal;

  csr_file dut (.i_retire_hold(1'b0), .i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_mret_take(mret_take), .i_mtime(mtime));

  initial assume (reset);
  always @(*) assume (op[1:0] != 2'b00);

  wire has_effect = op[1:0] == 2'b01 || !src_zero;
  reg f_past = 0;
  always @(posedge clk) f_past <= 1;

  always @(posedge clk) if (f_past && !reset) begin
    if (addr == 12'hC01) assert (rdata == mtime[31:0]);
    if (addr == 12'hC81) assert (rdata == mtime[63:32]);
    if ((addr == 12'hC01 || addr == 12'hC81) && has_effect) assert (illegal);
    if ((addr == 12'hC01 || addr == 12'hC81) && !has_effect) assert (!illegal);
`ifdef COVER
    cover (addr == 12'hC81 && mtime[63:32] != 0 && !illegal);
    cover (addr == 12'hC01 && has_effect && illegal);
`endif
  end
endmodule
