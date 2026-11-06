// Properties of the Sscofpmf extension in csr_file (has_zihpm, has_interrupts and has_sscofpmf on), checked on the
// Verilog netlist that GHDL synthesizes from the VHDL. NHPM is the number of real event counters, WIDTH their width in
// bits (at most 32, so a counter is one half). A symbolic index k (any index from 3 to 31, fixed for the whole run)
// stands for all counters. A model keeps what the extension defines for counter k, with the 32-bit CSR halves:
//  - the counter adds 1 in a cycle when its event is selected (a code of the table, not 0), the event vector has the
//    bit, mcountinhibit is not used (the proof assumes no write to it) and MINH is clear;
//  - an increment of the all-ones counter, with no write to the counter in the same cycle, is an overflow; two
//    cycles later the overflow has set OF; if OF was clear, it also sets LCOFIP in mip;
//  - OF and MINH are written by the CSR instructions at mhpmeventkh (0x720 + k), bits 31 and 30, and an overflow
//    wins over a write that clears OF in its cycle; LCOFIP is written by mip (bit 13), the overflow wins; LCOFIE is
//    bit 13 of mie. The timer line (MTIP) is the only other interrupt source, and has a higher priority.
// Whatever the CSR instructions do:
//  1. mhpmeventkh reads OF in bit 31, MINH in bit 30 and zero elsewhere, and is never illegal at a real index;
//     at an index past the real counters it reads zero and ignores writes;
//  2. mip bit 13 reads LCOFIP, mie bit 13 reads LCOFIE, and no other bit of the two reads above bit 11;
//  3. an overflow with OF clear raises LCOFIP, and one with OF set does not;
//  4. o_irq_pending is the timer or LCOFI pending and enabled, o_irq_take adds mstatus.MIE, and the cause is the
//     timer one (0x80000007) before LCOFI (0x8000000D);
//  5. the counter value is the model's;
//  6. the range of mhpmeventkh does not alias the range 0xF20 to 0xF3F, which is illegal.
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take, irq_tm;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [15:0] events;
  (* anyconst *) wire [4:0] k;
  wire [31:0] rdata, cause;
  wire illegal, pending, take;

  csr_file dut (.i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_mret_take(mret_take), .i_events(events), .i_irq_timer(irq_tm), .i_irq_software(1'b0), .i_irq_external(1'b0), .o_irq_pending(pending),
    .o_irq_take(take), .o_irq_cause(cause));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);
  always @(*) assume (op[1:0] != 2'b00);
  always @(*) assume (k >= 3);

  localparam N = `NHPM;
  localparam W = `WIDTH;
  localparam [31:0] MASK = 32'hFFFFFFFF >> (32 - W);
  wire k_real = (k - 5'd3) < N;
  wire has_effect = op[1:0] == 2'b01 || !src_zero;
  wire plain_write = commit && !trap_take && !mret_take && has_effect;
  // mcountinhibit is outside this proof, and so are the other counters: LCOFIP is raised by any counter, so only
  // counter k selects an event and the others stay at event 0, which never counts.
  always @(*) assume (!(commit && addr == 12'h320));
  always @(*) assume (!(commit && has_effect && addr[11:5] == 7'h19 && addr[4:0] >= 5'd3 && addr[4:0] != k));

  reg f_past = 0;
  reg [31:0] m_cnt = 0;
  reg [3:0] m_code = 0;
  reg m_of = 0, m_minh = 0, m_lcofip = 0, m_ie = 0, m_pie = 0;
  reg [31:0] m_mie = 0;
  wire m_lcofie = m_mie[13], m_mtie = m_mie[7];
  reg m_ovf1 = 0;

  wire [31:0] new_val = op[1:0] == 2'b01 ? wdata : op[1:0] == 2'b10 ? (rdata | wdata) : (rdata & ~wdata);
  wire ev_sel = k_real && m_code != 4'd0 && m_code <= 4'd9 && events[m_code];
  wire inc = ev_sel && !m_minh;
  wire lo_we = plain_write && addr == {7'h58, k} && k_real;
  wire ovf_now = inc && !lo_we && m_cnt == MASK;
  wire req = m_ovf1 && !m_of;

  always @(posedge clk) begin
    f_past <= 1;
    if (reset) begin
      m_cnt <= 0; m_code <= 0; m_of <= 0; m_minh <= 0; m_lcofip <= 0; m_mie <= 0;
      m_ie <= 0; m_pie <= 0; m_ovf1 <= 0;
    end else begin
      m_ovf1 <= ovf_now;
      if (lo_we) m_cnt <= new_val & MASK; else if (inc) m_cnt <= (m_cnt + 1) & MASK;
      if (plain_write && addr == {7'h19, k} && k_real) m_code <= new_val[3:0];
      if (m_ovf1) m_of <= 1; else if (plain_write && addr == {7'h39, k} && k_real) m_of <= new_val[31];
      if (plain_write && addr == {7'h39, k} && k_real) m_minh <= new_val[30];
      if (req) m_lcofip <= 1;
      else if (plain_write && addr == 12'h344) m_lcofip <= new_val[13];
      if (plain_write && addr == 12'h304) m_mie <= new_val & 32'h00002888;
      if (trap_take) begin m_pie <= m_ie; m_ie <= 0; end
      else if (mret_take) begin m_ie <= m_pie; m_pie <= 1; end
      else if (plain_write && addr == 12'h300) begin m_ie <= new_val[3]; m_pie <= new_val[7]; end
    end
  end

  wire lcofi_pend = m_lcofip && m_lcofie;
  wire timer_pend = irq_tm && m_mtie;

  always @(posedge clk) if (f_past && !reset) begin
    if (addr == {7'h39, k}) begin
      assert (!illegal);
      assert (rdata == (k_real ? {m_of, m_minh, 30'b0} : 32'h0));
    end
    if (addr == 12'h344) assert (rdata == ((m_lcofip ? 32'h2000 : 32'h0) | (irq_tm ? 32'h80 : 32'h0)));
    if (addr == 12'h304) assert (rdata == m_mie);
    if (addr == {7'h58, k} && k_real) assert (rdata == m_cnt);
    // The range does not alias another one: 0xF20 to 0xF3F is nothing the core has.
    if (addr[11:5] == 7'h79) assert (illegal);
    assert (pending == (lcofi_pend || timer_pend));
    assert (take == ((lcofi_pend || timer_pend) && m_ie));
    if (pending) assert (cause == (timer_pend ? 32'h80000007 : 32'h8000000D));
`ifdef COVER
    cover (m_ovf1 && !m_of);
    cover (m_ovf1 && m_of);
    cover (m_lcofip && m_lcofie && !irq_tm && take);
    cover (lcofi_pend && timer_pend);
    cover (plain_write && addr == {7'h39, k} && k_real && !new_val[31] && m_of);
    cover (plain_write && addr == 12'h344 && !new_val[13] && m_lcofip);
    cover (m_minh && ev_sel);
`endif
  end
endmodule
