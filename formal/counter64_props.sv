// Properties of counter64, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// A model keeps the ideal 64-bit value of the counter. Whatever the inputs do, the value the
// counter shows (the high half with the pending carry summed) is the model's value: it counts one
// per increment, a write wins over the increment of its own cycle, and the carry between the
// halves is never lost.
module props (input clk);
  (* anyseq *) wire reset, inc, we_lo, we_hi;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] lo, hi;

  counter64 dut (.i_clk(clk), .i_rst(reset), .i_inc(inc), .i_we_lo(we_lo), .i_we_hi(we_hi),
    .i_wdata(wdata), .o_lo(lo), .o_hi(hi));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);

  reg f_past = 0;
  reg [63:0] model = 64'h0;
  reg [31:0] p_lo = 0, p_hi = 0;
  reg p_reset = 0, p_inc = 0, p_we_lo = 0, p_we_hi = 0;

  // The ideal counter: the low half takes the write or the increment, the high half takes the write
  // (or keeps its value) and then the carry that the low half produced in this cycle.
  wire        carry_out = inc && !we_lo && model[31:0] == 32'hFFFFFFFF;
  wire [31:0] lo_next   = we_lo ? wdata : (inc ? model[31:0] + 32'd1 : model[31:0]);
  wire [31:0] hi_base   = we_hi ? wdata : model[63:32];
  wire [31:0] hi_next   = hi_base + {31'b0, carry_out};

  always @(posedge clk) begin
    f_past <= 1;
    p_lo <= lo; p_hi <= hi;
    p_reset <= reset; p_inc <= inc; p_we_lo <= we_lo; p_we_hi <= we_hi;
    model <= reset ? 64'h0 : {hi_next, lo_next};
  end

  // The registers clear asynchronously: while reset is high a read gives the reset value.
  always @(posedge clk) if (f_past && !reset) begin
    // 1. The value shown is the ideal 64-bit value, in every cycle.
    assert ({hi, lo} == model);
  end

`ifdef MONOTONIC
  // 2. Without a write in the previous cycle the 64-bit value never decreases (it can wrap at 2^64).
  always @(posedge clk) if (f_past && !p_reset && !reset && !p_we_lo && !p_we_hi && {p_hi, p_lo} != 64'hFFFFFFFFFFFFFFFF)
    assert ({hi, lo} >= {p_hi, p_lo});
`endif

`ifdef COVER
  // The carry between the halves is reachable, and a write together with the wrap.
  always @(posedge clk) if (f_past && !reset) begin
    cover (p_inc && p_lo == 32'hFFFFFFFF && lo == 32'h0 && hi == p_hi + 1);
    cover (p_we_hi && p_lo == 32'hFFFFFFFF && p_inc);
  end
`endif
endmodule
