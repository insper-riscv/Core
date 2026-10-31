// Properties of csr_file with Zicntr, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// Two 64-bit models keep the ideal values of mcycle and minstret. A retirement is added to minstret one
// cycle after it happens, unless the cancel input of that cycle removes it, and a read already shows it. Whatever the CSR instructions do,
// the value read at 0xB00/0xB80/0xC00/0xC80 (mcycle and cycle) and 0xB02/0xB82/0xC02/0xC82
// (minstret and instret) is the model's value; a write lands in the half it addresses and wins over
// the increment of its own cycle; the read-only mirrors and time reject every write. Bits 0 and 2 of
// mcountinhibit (0x320) stop mcycle and minstret, and the register reads back what was written to them.
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take, retire, retire_cancel;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata;
  wire [31:0] rdata;
  wire illegal;

  csr_file dut (.i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_mret_take(mret_take), .i_retire(retire), .i_retire_cancel(retire_cancel));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);
  always @(*) assume (op[1:0] != 2'b00);

  localparam [11:0] MCYCLE = 12'hB00, MCYCLEH = 12'hB80, MINSTRET = 12'hB02, MINSTRETH = 12'hB82,
                    CYCLE = 12'hC00, CYCLEH = 12'hC80, TIME = 12'hC01, TIMEH = 12'hC81,
                    INSTRET = 12'hC02, INSTRETH = 12'hC82;

  wire is_cycle_lo   = addr == MCYCLE   || addr == CYCLE;
  wire is_cycle_hi   = addr == MCYCLEH  || addr == CYCLEH;
  wire is_instret_lo = addr == MINSTRET || addr == INSTRET;
  wire is_instret_hi = addr == MINSTRETH || addr == INSTRETH;
  wire is_time       = addr == TIME || addr == TIMEH;
  wire is_inhibit    = addr == 12'h320;
  wire is_counter    = is_inhibit || is_cycle_lo || is_cycle_hi || is_instret_lo || is_instret_hi || is_time;

  reg f_past = 0;
  reg [63:0] m_cycle = 64'h0, m_instret = 64'h0;
  // The retirement of the previous cycle, not yet added to the model of minstret.
  reg m_pending = 0;
  // Bit 0 and bit 2 of mcountinhibit.
  reg m_inh0 = 0, m_inh2 = 0;

  // The value a CSR instruction writes: the same read-modify-write the register file performs.
  // What a program reads of minstret: the counter and the pending retirement.
  wire [63:0] instret_seen = m_instret + {63'b0, m_pending && !m_inh2};
  wire [31:0] old_value = is_inhibit ? {29'b0, m_inh2, 1'b0, m_inh0} : is_cycle_lo ? m_cycle[31:0] : is_cycle_hi ? m_cycle[63:32] :
                          is_instret_lo ? instret_seen[31:0] : instret_seen[63:32];
  wire [31:0] new_value = op[1:0] == 2'b01 ? wdata : op[1:0] == 2'b10 ? (old_value | wdata) : (old_value & ~wdata);
  wire has_effect = op[1:0] == 2'b01 || !src_zero;
  // A write reaches a counter only through the writable address of it, without a trap or an MRET.
  wire write = commit && has_effect && !trap_take && !mret_take;
  wire we_cycle_lo   = write && addr == MCYCLE;
  wire we_cycle_hi   = write && addr == MCYCLEH;
  wire we_instret_lo = write && addr == MINSTRET;
  wire we_instret_hi = write && addr == MINSTRETH;

  wire        we_inhibit = write && is_inhibit;
  wire        cy_carry = !m_inh0 && !we_cycle_lo && m_cycle[31:0] == 32'hFFFFFFFF;
  wire [31:0] cy_lo = we_cycle_lo ? new_value : (m_inh0 ? m_cycle[31:0] : m_cycle[31:0] + 32'd1);
  wire [31:0] cy_hi = (we_cycle_hi ? new_value : m_cycle[63:32]) + {31'b0, cy_carry};
  wire        pinc = m_pending && !retire_cancel && !m_inh2;
  wire        in_carry = pinc && !we_instret_lo && m_instret[31:0] == 32'hFFFFFFFF;
  wire [31:0] in_lo = we_instret_lo ? new_value : (pinc ? m_instret[31:0] + 32'd1 : m_instret[31:0]);
  wire [31:0] in_hi = (we_instret_hi ? new_value : m_instret[63:32]) + {31'b0, in_carry};

  always @(posedge clk) begin
    f_past <= 1;
    m_cycle   <= reset ? 64'h0 : {cy_hi, cy_lo};
    m_instret <= reset ? 64'h0 : {in_hi, in_lo};
    m_inh0 <= reset ? 1'b0 : we_inhibit ? new_value[0] : m_inh0;
    m_inh2 <= reset ? 1'b0 : we_inhibit ? new_value[2] : m_inh2;
    m_pending <= reset ? 1'b0 : (retire && !we_instret_lo && !we_instret_hi);
  end

  // While reset is high a read gives the reset value, so the properties apply to the clocks without reset.
  always @(posedge clk) if (f_past && !reset) begin
    // 1. Every counter address is a legal read; a write to a read-only mirror or to time is illegal.
    if (is_counter && addr[11:10] == 2'b11 && has_effect) assert (illegal);
    if (is_counter && !(addr[11:10] == 2'b11 && has_effect)) assert (!illegal);
    // 2. The value read is the ideal 64-bit value of the half the address selects.
    if (is_inhibit)    assert (rdata == {29'b0, m_inh2, 1'b0, m_inh0});
    if (is_cycle_lo)   assert (rdata == m_cycle[31:0]);
    if (is_cycle_hi)   assert (rdata == m_cycle[63:32]);
    if (is_instret_lo) assert (rdata == instret_seen[31:0]);
    if (is_instret_hi) assert (rdata == instret_seen[63:32]);
  end

`ifdef COVER
  always @(posedge clk) if (f_past && !reset) begin
    cover (we_cycle_hi && m_cycle[31:0] == 32'hFFFFFFFF);
    cover (m_pending && m_instret[31:0] == 32'hFFFFFFFF && !we_instret_lo);
    cover (we_instret_lo && retire);
    cover (m_pending && retire_cancel);
  end
`endif
endmodule
