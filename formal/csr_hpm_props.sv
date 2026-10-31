// Properties of csr_file with Zihpm, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// A model keeps, for each event counter, the 64-bit value, the selected event code and the bit of
// mcountinhibit. A counter adds 1 in a cycle when the event vector has the selected bit set, the code is
// not 0 and the counter is not inhibited; a write lands in the half it addresses and wins over the
// increment of its own cycle. Whatever the CSR instructions do, what a program reads at mcountinhibit
// (0x320), mhpmeventN (0x320 + N), mhpmcounterN and its mirror (0xB00 + N, 0xC00 + N) and the high halves
// (0xB80 + N, 0xC80 + N) is the model's value, the mirrors reject every write, and the addresses of the
// counters the profile does not have are illegal. NHPM is the number of event counters and HAS_CNTR says
// whether mcycle and minstret exist (they own bits 0 and 2 of mcountinhibit).
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata;
  (* anyseq *) wire [15:0] events;
  wire [31:0] rdata;
  wire illegal;

  csr_file dut (.i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_mret_take(mret_take), .i_events(events));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);
  always @(*) assume (op[1:0] != 2'b00);

  localparam N = `NHPM;
`ifdef HAS_CNTR
  localparam [6:0] MASK_BASE = 7'b0000101;
`else
  localparam [6:0] MASK_BASE = 7'b0000000;
`endif
  localparam [6:0] MASK = MASK_BASE | (((7'd1 << N) - 7'd1) << 3);

  reg f_past = 0;
  reg [6:0] m_inh = 7'h0;
  reg [63:0] m_cnt [0:3];
  reg [3:0] m_code [0:3];
  integer i;
  initial for (i = 0; i < 4; i = i + 1) begin m_cnt[i] = 64'h0; m_code[i] = 4'h0; end

  // The value a CSR instruction writes: the read-modify-write the register file performs.
  reg [31:0] old_value;
  always @(*) begin
    old_value = 32'h0;
    if (addr == 12'h320) old_value = {25'b0, m_inh};
    for (i = 0; i < 4; i = i + 1) begin
      if (addr == 12'h323 + i) old_value = {28'b0, m_code[i]};
      if (addr == 12'hB03 + i || addr == 12'hC03 + i) old_value = m_cnt[i][31:0];
      if (addr == 12'hB83 + i || addr == 12'hC83 + i) old_value = m_cnt[i][63:32];
    end
  end
  wire [31:0] new_value = op[1:0] == 2'b01 ? wdata : op[1:0] == 2'b10 ? (old_value | wdata) : (old_value & ~wdata);
  wire has_effect = op[1:0] == 2'b01 || !src_zero;
  wire write = commit && has_effect && !trap_take && !mret_take;

  // Is the address one of the registers of the profile?
  reg present, mirror;
  always @(*) begin
    present = addr == 12'h320;
    mirror = 1'b0;
    for (i = 0; i < N; i = i + 1) begin
      if (addr == 12'h323 + i || addr == 12'hB03 + i || addr == 12'hB83 + i) present = 1'b1;
      if (addr == 12'hC03 + i || addr == 12'hC83 + i) begin present = 1'b1; mirror = 1'b1; end
    end
  end
  // The addresses of the counters the profile does not have.
  reg absent;
  always @(*) begin
    absent = 1'b0;
    for (i = N; i < 4; i = i + 1)
      if (addr == 12'h323 + i || addr == 12'hB03 + i || addr == 12'hB83 + i || addr == 12'hC03 + i || addr == 12'hC83 + i)
        absent = 1'b1;
  end

  reg [3:0] inc;
  always @(*) for (i = 0; i < 4; i = i + 1)
    inc[i] = events[m_code[i]] && m_code[i] != 4'h0 && !m_inh[3 + i];

  always @(posedge clk) begin
    f_past <= 1;
    if (reset) begin
      m_inh <= 7'h0;
      for (i = 0; i < 4; i = i + 1) begin m_cnt[i] <= 64'h0; m_code[i] <= 4'h0; end
    end else begin
      if (write && addr == 12'h320) m_inh <= new_value[6:0] & MASK;
      for (i = 0; i < 4; i = i + 1) begin
        if (i < N) begin
          if (write && addr == 12'h323 + i) m_code[i] <= new_value[3:0];
          m_cnt[i] <= {(write && addr == 12'hB83 + i ? new_value : m_cnt[i][63:32]) +
                         {31'b0, inc[i] && !(write && addr == 12'hB03 + i) && m_cnt[i][31:0] == 32'hFFFFFFFF},
                       write && addr == 12'hB03 + i ? new_value : m_cnt[i][31:0] + {31'b0, inc[i]}};
        end
      end
    end
  end

  // While reset is high a read gives the reset value, so the properties apply to the clocks without reset.
  always @(posedge clk) if (f_past && !reset) begin
    // 1. A register of the profile is a legal read, and a write to a mirror is illegal.
    if (present) assert (illegal == (mirror && has_effect));
    // 2. The addresses of a counter the profile lacks are illegal.
    if (absent) assert (illegal);
    // 3. What is read is the model's value.
    if (addr == 12'h320) assert (rdata == {25'b0, m_inh});
    for (i = 0; i < N; i = i + 1) begin
      if (addr == 12'h323 + i) assert (rdata == {28'b0, m_code[i]});
      if (addr == 12'hB03 + i || addr == 12'hC03 + i) assert (rdata == m_cnt[i][31:0]);
      if (addr == 12'hB83 + i || addr == 12'hC83 + i) assert (rdata == m_cnt[i][63:32]);
    end
  end

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (inc[0] && m_cnt[0][31:0] == 32'hFFFFFFFF);
    cover (m_code[0] != 4'h0 && events[m_code[0]] && m_inh[3]);
    cover (write && addr == 12'hB03 && inc[0]);
    cover (write && addr == 12'h320 && new_value[3]);
    cover (inc[N-1] && write && addr == 12'hB83 + N - 1);
  end
`endif
endmodule
