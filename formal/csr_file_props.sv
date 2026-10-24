// Properties of csr_file, checked on the Verilog netlist that GHDL synthesizes from the VHDL.
// The inputs are free; the only assumption is that the pipeline never commits a CSR operation with
// op[1:0] = 00 (funct3 = 000 and 100 are not CSR accesses).
module props (input clk);
  (* anyseq *) wire reset, commit, src_zero, trap_take, mret_take;
  (* anyseq *) wire [11:0] addr;
  (* anyseq *) wire [2:0] op;
  (* anyseq *) wire [31:0] wdata, trap_cause, trap_pc, trap_tval;
  wire [31:0] rdata, mtvec_o, mepc_o;
  wire illegal;

  csr_file dut (.i_clk(clk), .i_rst(reset), .i_commit(commit), .i_addr(addr), .i_op(op), .i_wdata(wdata),
    .i_src_zero(src_zero), .o_rdata(rdata), .o_illegal(illegal), .i_trap_take(trap_take),
    .i_trap_cause(trap_cause), .i_trap_pc(trap_pc), .i_trap_tval(trap_tval), .i_mret_take(mret_take),
    .o_mtvec(mtvec_o), .o_mepc(mepc_o));

  always @(*) assume (op[1:0] != 2'b00);
`ifdef MSTATUS_MODE
  // The read port stays on mstatus, so rdata is the mstatus value of every cycle.
  always @(*) assume (addr == 12'h300);
  always @(*) assume (!(trap_take && mret_take));
`endif

  reg f_past = 0;
  reg [11:0] p_addr = 0; reg [2:0] p_op = 0; reg [31:0] p_rdata = 0, p_wdata = 0;
  reg p_reset = 0, p_commit = 0, p_src_zero = 0, p_trap = 0, p_mret = 0;
  reg [31:0] p_cause = 0, p_pc = 0, p_tval = 0;

  always @(posedge clk) begin
    f_past <= 1;
    p_addr <= addr; p_op <= op; p_rdata <= rdata; p_wdata <= wdata;
    p_reset <= reset; p_commit <= commit; p_src_zero <= src_zero; p_trap <= trap_take; p_mret <= mret_take;
    p_cause <= trap_cause; p_pc <= trap_pc; p_tval <= trap_tval;
  end

  wire p_event = p_reset || p_trap || p_mret || p_commit;
  wire p_plain_commit = p_commit && !p_reset && !p_trap && !p_mret;
  wire p_write = p_plain_commit && (p_op[1:0] == 2'b01 || !p_src_zero);
  wire [31:0] p_new = p_op[1:0] == 2'b01 ? p_wdata : p_op[1:0] == 2'b10 ? (p_rdata | p_wdata) : (p_rdata & ~p_wdata);

  // 1. The fixed bits never change.
  always @(*) begin
    if (addr == 12'h300) assert ((rdata & 32'hFFFFFF77) == 32'h00001800);
    if (addr == 12'h301) assert (rdata == 32'h40001100);
    if (addr == 12'h304 || addr == 12'h344 || addr == 12'h310 ||
        addr == 12'hF11 || addr == 12'hF12 || addr == 12'hF13 || addr == 12'hF14 || addr == 12'hF15)
      assert (rdata == 32'h0);
    if (addr == 12'h305 || addr == 12'h341) assert (rdata[1:0] == 2'b00);
    assert (mtvec_o[1:0] == 2'b00 && mepc_o[1:0] == 2'b00);
  end

  always @(posedge clk) if (f_past) begin
    // 2. Without commit, trap, MRET or reset no CSR changes.
    if (!p_event && addr == p_addr) assert (rdata == p_rdata);

    // 3. A write followed by a read of the same CSR returns the written value, masked.
    if (p_write && addr == p_addr) begin
      if (p_addr == 12'h340 || p_addr == 12'h342 || p_addr == 12'h343) assert (rdata == p_new);
      if (p_addr == 12'h305 || p_addr == 12'h341) assert (rdata == {p_new[31:2], 2'b00});
      if (p_addr == 12'h300) assert (rdata[3] == p_new[3] && rdata[7] == p_new[7]);
    end

    // 4. A trap updates mepc, mcause and mtval on the same edge (the trap wins over a commit).
    if (p_trap && !p_reset) begin
      if (addr == 12'h341) assert (rdata == {p_pc[31:2], 2'b00});
      if (addr == 12'h342) assert (rdata == p_cause);
      if (addr == 12'h343) assert (rdata == p_tval);
    end

    // 5. A reset clears every writable CSR.
    if (p_reset && addr == p_addr && p_addr != 12'h301) assert (p_addr == 12'h300 ? rdata == 32'h1800 : rdata == 32'h0);

`ifdef MSTATUS_MODE
    // 6. A trap saves MIE in MPIE and clears MIE; MRET restores MIE and sets MPIE.
    if (p_trap && !p_reset) assert (rdata[3] == 1'b0 && rdata[7] == p_rdata[3]);
    if (p_mret && !p_trap && !p_reset) assert (rdata[3] == p_rdata[7] && rdata[7] == 1'b1);
`endif
  end

`ifdef COVER
  always @(posedge clk) if (f_past) begin
`ifdef MSTATUS_MODE
    cover (p_trap && !p_reset && p_rdata[3]);
    cover (p_mret && !p_trap && !p_reset && rdata[3] && !p_rdata[3]);
`else
    cover (p_write && p_addr == 12'h305);
    cover (p_commit && p_trap);
`endif
  end
`endif
endmodule
