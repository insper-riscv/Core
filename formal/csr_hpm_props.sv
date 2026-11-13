// Properties of csr_file with Zihpm, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// NHPM is the number of real event counters (hpm_counters), WIDTH their width in bits (hpm_width) and
// HAS_CNTR says whether mcycle and minstret exist (they own bits 0 and 2 of mcountinhibit).
//
// The 29 counters share one structure, so a symbolic index k (any index from 3 to 31, fixed for the whole
// run) stands for all of them: a model keeps the counter k, its event code and its inhibit bit. A counter
// adds 1 in a cycle when the event vector has the selected bit set, the code is in the table, the code is
// not 0 and the counter is not inhibited; a write lands in the half it addresses, keeps only the bits
// that fit in the width, and wins over the increment of its own cycle. Whatever the CSR instructions do:
//  1. the five ranges (0x320, 0xB00, 0xB80, 0xC00, 0xC80) hold an address for every index from 3 to 31,
//     none of them is illegal to read, and a write to a mirror (0xC00 and 0xC80 ranges) is illegal;
//  2. the addresses the privileged chapter does not define (0x321, 0x322, 0xB01 and 0xB81) are illegal;
//  3. an index at or past NHPM reads zero in the four registers and in the inhibit bit, and ignores writes;
//  4. what is read at the address of counter k is the model's value, in the machine range and in the mirror;
//  5. the inhibit bits past NHPM, bit 1 and, without Zicntr, bits 0 and 2 read zero;
//  6. the ranges do not overlap other addresses: an address outside the five ranges (at index 3 or more)
//     that is not another CSR of the core is illegal.
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [15:0] events;
  (* anyconst *) wire [4:0] k;
  wire [31:0] rdata;
  wire illegal;

  csr_file dut (.i_retire_hold(1'b0), .i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_mret_take(mret_take), .i_events(events));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);
  always @(*) assume (op[1:0] != 2'b00);
  always @(*) assume (k >= 3);

  localparam N = `NHPM;
`ifdef WIDTH
  localparam W = `WIDTH;
`else
  localparam W = 64;
`endif
  localparam LW = W < 32 ? W : 32;
  localparam [31:0] LO_MASK = LW == 0 ? 32'h0 : (32'hFFFFFFFF >> (32 - LW));
  localparam [31:0] HI_MASK = W <= 32 ? 32'h0 : (32'hFFFFFFFF >> (64 - W));
  // A counter with width 0 is not real.
  localparam REAL = W == 0 ? 0 : N;
`ifdef HAS_CNTR
  localparam [31:0] CNTR_BITS = 32'h5;
`else
  localparam [31:0] CNTR_BITS = 32'h0;
`endif

  wire [6:0] range = addr[11:5];
  wire [4:0] idx = addr[4:0];
  wire in_event   = range == 7'h19;
  wire in_mlo     = range == 7'h58;
  wire in_mhi     = range == 7'h5C;
  wire in_lo_mirr = range == 7'h60;
  wire in_hi_mirr = range == 7'h64;
  wire in_hpm_range = in_event || in_mlo || in_mhi || in_lo_mirr || in_hi_mirr;
  wire is_inhibit = in_event && idx == 5'd0;
  wire is_mirror = in_lo_mirr || in_hi_mirr;
  wire has_effect = op[1:0] == 2'b01 || !src_zero;
  wire real_idx = idx >= 5'd3 && (idx - 5'd3) < REAL;

  // The CSRs of the core that are not event counters: Zicsr, the identification registers, mcountinhibit
  // and, with Zicntr, the six counters and their halves.
  wire defined_other = addr == 12'h300 || addr == 12'h301 || addr == 12'h304 || addr == 12'h305 || addr == 12'h310 ||
                       (addr >= 12'h340 && addr <= 12'h344) || (addr >= 12'hF11 && addr <= 12'hF15) || addr == 12'h320
`ifdef HAS_CNTR
                       || addr == 12'hB00 || addr == 12'hB02 || addr == 12'hB80 || addr == 12'hB82 ||
                       addr == 12'hC00 || addr == 12'hC01 || addr == 12'hC02 ||
                       addr == 12'hC80 || addr == 12'hC81 || addr == 12'hC82
`endif
                       ;

  // The model: counter k, its code and its inhibit bit, and bits 0 and 2 of mcountinhibit.
  wire k_real = (k - 5'd3) < REAL;
  reg f_past = 0;
  reg [63:0] m_cnt = 64'h0;
  reg [3:0] m_code = 4'h0;
  reg m_inh = 1'b0;
  reg m_inh0 = 1'b0, m_inh2 = 1'b0;

  wire at_event = in_event && idx == k;
  wire at_lo = (in_mlo || in_lo_mirr) && idx == k;
  wire at_hi = (in_mhi || in_hi_mirr) && idx == k;

  // The value a CSR instruction writes: the read-modify-write the register file performs.
  reg [31:0] old_value;
  always @(*) begin
    old_value = 32'h0;
    if (is_inhibit) begin
      old_value = {29'b0, m_inh2, 1'b0, m_inh0};
      if (k_real) old_value[k] = m_inh;
    end
    if (k_real) begin
      if (at_event) old_value = {28'b0, m_code};
      if (at_lo) old_value = m_cnt[31:0];
      if (at_hi) old_value = m_cnt[63:32];
    end
  end
  wire [31:0] new_value = op[1:0] == 2'b01 ? wdata : op[1:0] == 2'b10 ? (old_value | wdata) : (old_value & ~wdata);
  wire write = commit && has_effect && !trap_take && !mret_take;

  wire [15:0] valid_events = events & 16'h03FE;
  wire inc = valid_events[m_code] && !m_inh;
  wire write_lo = write && in_mlo && idx == k;
  wire write_hi = write && in_mhi && idx == k;
  wire carry = k_real && inc && !write_lo && (m_cnt[31:0] & LO_MASK) == LO_MASK;

  always @(posedge clk) begin
    f_past <= 1;
    if (reset) begin
      m_cnt <= 64'h0; m_code <= 4'h0; m_inh <= 1'b0; m_inh0 <= 1'b0; m_inh2 <= 1'b0;
    end else begin
      if (k_real) begin
        if (write && in_event && idx == k) m_code <= new_value[3:0];
        m_cnt[31:0] <= write_lo ? (new_value & LO_MASK) : (inc ? ((m_cnt[31:0] + 32'd1) & LO_MASK) : m_cnt[31:0]);
        m_cnt[63:32] <= ((write_hi ? (new_value & HI_MASK) : m_cnt[63:32]) + {31'b0, carry}) & HI_MASK;
      end
      if (write && is_inhibit) begin
        if (k_real) m_inh <= new_value[k];
        m_inh0 <= new_value[0] && (CNTR_BITS[0]);
        m_inh2 <= new_value[2] && (CNTR_BITS[2]);
      end
    end
  end

  // While reset is high a read gives the reset value, so the properties apply to the clocks without reset.
  always @(posedge clk) if (f_past && !reset) begin
    // 1. Every address of the five ranges at an index from 3 to 31 is legal to read, a mirror is read-only.
    if (in_hpm_range && idx >= 5'd3) assert (illegal == (is_mirror && has_effect));
    if (is_inhibit) assert (!illegal);
    // 2. The addresses of the ranges that the privileged chapter does not define are illegal.
    if (addr == 12'h321 || addr == 12'h322 || addr == 12'hB01 || addr == 12'hB81) assert (illegal);
    // 6. No other address is known.
    if (!(in_hpm_range && idx >= 5'd3) && !defined_other) assert (illegal);
    // 3. An index without a real counter reads zero everywhere.
    if (in_hpm_range && idx >= 5'd3 && !real_idx) assert (rdata == 32'h0);
    // 4. What is read is the model's value.
    if (k_real) begin
      if (at_event) assert (rdata == {28'b0, m_code});
      if (at_lo) assert (rdata == m_cnt[31:0]);
      if (at_hi) assert (rdata == m_cnt[63:32]);
    end
    // 5. The inhibit register: the bit of counter k, the bits of the indices without a counter and the
    // reserved bits.
    if (is_inhibit) begin
      if (k_real) assert (rdata[k] == m_inh);
      assert (rdata[0] == m_inh0 && rdata[2] == m_inh2 && rdata[1] == 1'b0);
      for (int j = 3; j < 32; j = j + 1)
        if (j - 3 >= REAL) assert (rdata[j] == 1'b0);
    end
  end

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (k_real && inc && m_cnt[31:0] == LO_MASK);
    cover (k_real && m_code != 4'h0 && valid_events[m_code] && m_inh);
    cover (write_lo && inc);
    cover (write && is_inhibit && new_value[k]);
    cover (k_real && inc && write_hi);
    cover (!k_real && write && in_mlo && idx == k);
  end
`endif
endmodule
