// Properties of mip and mie in csr_file, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// With the interrupts on (the default of this file) or off (-DOFF, the generic has_interrupts false). The
// three lines of interrupt are free inputs, a model keeps the three mask bits of mie, and a bit of mip or of
// mie is only at positions 3 (software), 7 (timer) and 11 (external). Whatever the CSR instructions do:
//  1. mip reads exactly the three lines at their positions and zero elsewhere (with the interrupts off, zero);
//  2. mie reads the model: the written bits of positions 3, 7 and 11, zero elsewhere, zero at reset (with the
//     interrupts off, always zero);
//  3. a write to mip is legal and changes nothing, and mie and mip are never illegal addresses;
//  4. o_irq_pending is 1 exactly when some line is 1 with its mask bit 1, whatever mstatus holds (with the
//     interrupts off, always 0);
//  5. o_irq_take is 1 exactly when o_irq_pending is 1 and mstatus.MIE is 1, a bit a model keeps from the traps,
//     the MRETs and the writes to mstatus;
//  6. o_irq_cause is the external cause (0x8000000B) when that line is pending and enabled, else the software
//     cause (0x80000003) when that one is, else the timer cause (0x80000007);
//  7. mtvec keeps BASE in bits 31:2 and the mode in bit 0, which only exists with the interrupts on; bit 1 reads
//     zero, and in the vectored mode BASE bits 5:2 read zero (64 bytes of alignment); o_mtvec is BASE with the
//     two low bits zero and o_mtvec_vectored is the mode.
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata, trap_cause, trap_pc, trap_tval;
  (* anyseq *) wire irq_sw, irq_tm, irq_ex;
  // Sondas: os registradores internos da unidade, ligados pelo script (formal/run.sh, PROBES) a nets da netlist.
  wire [2:0] pr_en;
  wire pr_mie, pr_mpie, pr_mode;
  wire [31:0] pr_mtvec;
  wire [31:0] rdata, mtvec_o, mepc_o;
  wire illegal, pending, take, vec;
  wire [31:0] cause;

  csr_file dut (.i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_trap_cause(trap_cause), .i_trap_pc(trap_pc), .i_trap_tval(trap_tval), .i_mret_take(mret_take),
    .o_mtvec(mtvec_o), .o_mepc(mepc_o), .i_irq_software(irq_sw), .i_irq_timer(irq_tm),
    .i_irq_external(irq_ex), .o_irq_pending(pending), .o_irq_take(take), .o_irq_cause(cause),
    .o_mtvec_vectored(vec));

  // The registers have no initial value: the first clock is a reset, as on the board.
  initial assume (reset);
  always @(*) assume (op[1:0] != 2'b00);

  localparam [31:0] POS = 32'h00000888;
`ifdef OFF
  localparam [31:0] LINES_MASK = 32'h0;
`else
  localparam [31:0] LINES_MASK = POS;
`endif
  wire [31:0] lines = ((irq_sw ? 32'h8 : 32'h0) | (irq_tm ? 32'h80 : 32'h0) | (irq_ex ? 32'h800 : 32'h0)) & LINES_MASK;

  // The model of mie: one write per clock, with the value the instruction computes from the old value.
  reg [31:0] m_mie = 0;
  // The model of mstatus.MIE and MPIE, and of mtvec.
  reg m_ie = 0, m_pie = 0;
  reg [31:0] m_mtvec = 0;
  reg f_past = 0;
  wire plain_write = commit && !trap_take && !mret_take && (op[1:0] == 2'b01 || !src_zero);
  wire [31:0] new_val = op[1:0] == 2'b01 ? wdata : op[1:0] == 2'b10 ? (rdata | wdata) : (rdata & ~wdata);

  always @(posedge clk) begin
    f_past <= 1;
    if (reset) begin
      m_mie <= 0; m_ie <= 0; m_pie <= 0; m_mtvec <= 0;
    end else begin
      if (plain_write && addr == 12'h304) m_mie <= new_val & LINES_MASK;
      if (trap_take) begin m_pie <= m_ie; m_ie <= 0; end
      else if (mret_take) begin m_ie <= m_pie; m_pie <= 1; end
      else if (plain_write && addr == 12'h300) begin m_ie <= new_val[3]; m_pie <= new_val[7]; end
      if (plain_write && addr == 12'h305)
        m_mtvec <= {new_val[31:6], (new_val[0] && LINES_MASK != 0) ? 4'b0 : new_val[5:2], 1'b0, new_val[0] && LINES_MASK != 0};
    end
  end

  wire [31:0] pend = lines & m_mie;

  // The registers clear asynchronously, so the properties about what they hold apply to the clocks without reset.
  always @(posedge clk) if (f_past && !reset) begin
    // Invariante de indução: o modelo é o estado dos registradores internos.
    assert (pr_en == {m_mie[11], m_mie[7], m_mie[3]});
    assert (pr_mie == m_ie);
    assert (pr_mpie == m_pie);
    assert (pr_mode == m_mtvec[0]);
    assert (!m_mtvec[1]);
    assert ((m_mie & ~LINES_MASK) == 32'h0);
    assert (pr_mtvec[31:2] == m_mtvec[31:2]);
    if (addr == 12'h344) assert (rdata == lines);
    if (addr == 12'h304) assert (rdata == m_mie);
    if (addr == 12'h304 || addr == 12'h344) assert (!illegal);
    assert (pending == ((lines & m_mie) != 32'h0));
    assert (take == (pending && m_ie));
    if (pending) assert (cause == (pend[11] ? 32'h8000000B : pend[3] ? 32'h80000003 : 32'h80000007));
    if (addr == 12'h305) assert (rdata == m_mtvec);
    assert (mtvec_o == {m_mtvec[31:2], 2'b00});
    assert (vec == m_mtvec[0]);
`ifdef COVER
    cover (pending && irq_tm && !irq_sw);
    cover (plain_write && addr == 12'h304 && new_val[7]);
    cover (plain_write && addr == 12'h344 && wdata != 0);
    cover (take && pend[11] && pend[3]);
    cover (take && pend[3] && pend[7] && !pend[11]);
    cover (pending && !m_ie);
    cover (vec);
    cover (plain_write && addr == 12'h305 && new_val[0] && new_val[5:2] != 0);
`endif
  end
endmodule
