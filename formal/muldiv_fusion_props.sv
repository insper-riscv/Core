// Properties of muldiv_fusion, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// A model keeps the last operation that ended in full (operands, funct3, the two halves of the full
// result). Whatever the units present, a hit happens only in the cycle after a start, with a record, the
// same two operand values, an operation of the same family (multiplication, signed division or unsigned
// division) and another operation than the recorded one; and in the cycle of a fused end the record shows
// exactly the full result that the earlier execution on those operands delivered. The operands and the
// funct3 of an instruction stay put from its start to the cycle that follows, as in the stalled EX stage.
module props (input clk);
  (* anyseq *) wire reset, start, done;
  (* anyseq *) wire [2:0] funct3, done_funct3;
  (* anyseq *) wire [31:0] a, b, full_lo, full_hi;
  wire hit, fuse;
  wire [31:0] rec_lo, rec_hi;

  muldiv_fusion dut (.i_clk(clk), .i_rst(reset), .i_start(start), .i_done(done), .i_funct3(funct3),
    .i_done_funct3(done_funct3), .i_a(a), .i_b(b), .i_full_lo(full_lo), .i_full_hi(full_hi),
    .o_hit(hit), .o_fuse(fuse), .o_rec_lo(rec_lo), .o_rec_hi(rec_hi));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);

  reg f_past = 0;
  reg p_start = 0;
  reg [31:0] p_a = 0, p_b = 0;
  reg [2:0] p_funct3 = 0;
  always @(posedge clk) begin
    f_past <= 1;
    p_start <= start && !reset;
    p_a <= a; p_b <= b; p_funct3 <= funct3;
    // An instruction holds its operands and funct3 in the cycle that follows its start.
    if (p_start) assume (a == p_a && b == p_b && funct3 == p_funct3);
  end

  // The model of the record and of the check cycle.
  reg m_valid = 0, m_check = 0, m_fuse = 0;
  reg [31:0] m_a = 0, m_b = 0, m_lo = 0, m_hi = 0;
  reg [2:0] m_funct3 = 0;
  always @(posedge clk) begin
    if (reset) begin
      m_valid <= 0; m_check <= 0; m_fuse <= 0;
      m_a <= 0; m_b <= 0; m_funct3 <= 0; m_lo <= 0; m_hi <= 0;
    end else begin
      m_check <= start;
      m_fuse <= hit;
      if (done) begin
        m_valid <= 1; m_a <= a; m_b <= b; m_funct3 <= done_funct3; m_lo <= full_lo; m_hi <= full_hi;
      end
    end
  end

  wire same_family = funct3[2] == m_funct3[2] && (funct3[2] == 1'b0 || funct3[0] == m_funct3[0]);
  wire want_hit = m_check && m_valid && a == m_a && b == m_b && same_family && funct3 != m_funct3;

  always @(posedge clk) if (f_past && !reset) begin
    // 1. The hit is exactly the rule: nothing else fuses, and every pair that the rule names does.
    assert (hit == want_hit);
    // 2. A fused end is the registered hit of the previous cycle.
    assert (fuse == m_fuse);
    // 3. The record always shows the full result of the last operation that ended in full.
    assert (rec_lo == m_lo && rec_hi == m_hi);
  end

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (hit);
    cover (fuse && funct3[2] == 1'b1);
    cover (fuse && funct3[2] == 1'b0);
    cover (m_check && m_valid && a == m_a && b == m_b && !same_family);
    cover (m_check && m_valid && a == m_a && b == m_b && same_family && funct3 == m_funct3);
  end
`endif
endmodule
