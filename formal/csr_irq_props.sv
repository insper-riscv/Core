// Properties of mip and mie in csr_file, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// With the interrupts on (the default of this file) or off (-DOFF, the generic has_interrupts false). The
// three lines of interrupt are free inputs, a model keeps the three mask bits of mie, and a bit of mip or of
// mie is only at positions 3 (software), 7 (timer) and 11 (external). Whatever the CSR instructions do:
//  1. mip reads exactly the three lines at their positions and zero elsewhere (with the interrupts off, zero);
//  2. mie reads the model: the written bits of positions 3, 7 and 11, zero elsewhere, zero at reset (with the
//     interrupts off, always zero);
//  3. a write to mip is legal and changes nothing, and mie and mip are never illegal addresses;
//  4. o_irq_pending is 1 exactly when some line is 1 with its mask bit 1, whatever mstatus holds (with the
//     interrupts off, always 0).
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata, trap_cause, trap_pc, trap_tval;
  (* anyseq *) wire irq_sw, irq_tm, irq_ex;
  wire [31:0] rdata, mtvec_o, mepc_o;
  wire illegal, pending;

  csr_file dut (.i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_trap_cause(trap_cause), .i_trap_pc(trap_pc), .i_trap_tval(trap_tval), .i_mret_take(mret_take),
    .o_mtvec(mtvec_o), .o_mepc(mepc_o), .i_irq_software(irq_sw), .i_irq_timer(irq_tm),
    .i_irq_external(irq_ex), .o_irq_pending(pending));

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
  reg f_past = 0;
  wire plain_write = commit && !trap_take && !mret_take && (op[1:0] == 2'b01 || !src_zero);
  wire [31:0] new_val = op[1:0] == 2'b01 ? wdata : op[1:0] == 2'b10 ? (rdata | wdata) : (rdata & ~wdata);

  always @(posedge clk) begin
    f_past <= 1;
    if (reset) m_mie <= 0;
    else if (plain_write && addr == 12'h304) m_mie <= new_val & LINES_MASK;
  end

  // The registers clear asynchronously, so the properties about what they hold apply to the clocks without reset.
  always @(posedge clk) if (f_past && !reset) begin
    if (addr == 12'h344) assert (rdata == lines);
    if (addr == 12'h304) assert (rdata == m_mie);
    if (addr == 12'h304 || addr == 12'h344) assert (!illegal);
    assert (pending == ((lines & m_mie) != 32'h0));
`ifdef COVER
    cover (pending && irq_tm && !irq_sw);
    cover (plain_write && addr == 12'h304 && new_val[7]);
    cover (plain_write && addr == 12'h344 && wdata != 0);
`endif
  end
endmodule
