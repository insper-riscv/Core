// Properties of the validity flags of reg_ex_mem (o_ok_rd and o_ok_wr) on the window of the peripherals, checked on the
// Verilog netlist GHDL synthesizes, with the map of the faults_map variant of formal/configs.yaml: BOOT_MEMORY and ROM
// in [0, 4 KiB), RAM in [8 KiB, 16 KiB), no external window and the peripherals from 0x80000000, in slots of 2**28
// bytes (bits 30:28), of which periph_slots = 00001001 occupies 0 and 3. Access faults on. By default the peripherals
// are strict (STRICT_PERIPH true): a slot without a peripheral refuses read and write. With -DLOOSE
// (STRICT_PERIPH false) every slot is accepted. A bubble (reset or flush) never refuses, and a frozen stage keeps its
// flags.
module props (input clk);
  (* anyseq *) wire rst, en, flush;
  (* anyseq *) wire [31:0] ea;
  (* anyseq *) wire [31:0] pc, alu_out, store_data;
  (* anyseq *) wire valid, we_reg, we_ram, re_ram, en_ram;
  (* anyseq *) wire [2:0] funct3, ext_ram_op;
  (* anyseq *) wire [3:0] byte_mask;
  (* anyseq *) wire [4:0] rd;
  (* anyseq *) wire [0:0] wb_sel;
  wire ok_rd, ok_wr;

  reg_ex_mem dut (
    .i_clk(clk), .i_rst(rst), .i_en(en), .i_flush(flush), .i_valid(valid), .i_pc(pc), .i_funct3(funct3),
    .i_alu_out(alu_out), .i_ea(ea), .i_store_data(store_data), .i_byte_mask(byte_mask), .i_rd(rd),
    .i_we_reg(we_reg), .i_we_ram(we_ram), .i_re_ram(re_ram), .i_en_ram(en_ram), .i_ext_ram_op(ext_ram_op),
    .i_wb_sel(wb_sel), .o_ok_rd(ok_rd), .o_ok_wr(ok_wr));

  // The model: what the stage holds, 0 before the first clock, 1 a bubble, 2 an address.
  reg [1:0] kind = 2'd0;
  reg [31:0] ea_q = 32'h0;
  always @(posedge clk) begin
    if (rst || flush) kind <= 2'd1;
    else if (en) begin kind <= 2'd2; ea_q <= ea; end
  end

  wire [7:0] slots = 8'b00001001;
  wire [2:0] slot = ea_q[30:28];
  wire in_periph = ea_q[31];
`ifdef LOOSE
  wire slot_ok = 1'b1;
`else
  wire slot_ok = slots[slot];
`endif
  wire in_ram = ea_q >= 32'h2000 && ea_q < 32'h4000;
  wire want_rd = ea_q < 32'h1000 || in_ram || (in_periph && slot_ok);
  wire want_wr = in_ram || (in_periph && slot_ok);

  always @(*) begin
    // 1. A bubble refuses nothing.
    if (kind == 2'd1) assert (ok_rd && ok_wr);
    // 2. The flags of a held address are the map: ROM reads, RAM reads and writes, the occupied slots both.
    if (kind == 2'd2) begin
      assert (ok_rd == want_rd);
      assert (ok_wr == want_wr);
    end
    // 3. A slot without a peripheral is refused when the peripherals are strict and accepted when they are not.
`ifdef LOOSE
    if (kind == 2'd2 && in_periph) assert (ok_rd && ok_wr);
`else
    if (kind == 2'd2 && in_periph && !slots[slot]) assert (!ok_rd && !ok_wr);
`endif
  end

`ifdef COVER
  always @(*) begin
    cover (kind == 2'd2 && in_periph && slots[slot] && ok_rd && ok_wr);
`ifdef LOOSE
    cover (kind == 2'd2 && in_periph && !slots[slot] && ok_rd && ok_wr);
`else
    cover (kind == 2'd2 && in_periph && !slots[slot] && !ok_rd && !ok_wr);
`endif
    cover (kind == 2'd2 && in_ram && ok_wr);
    cover (kind == 2'd2 && ea_q >= 32'h4000 && ea_q < 32'h80000000 && !ok_rd);
    cover (kind == 2'd1);
  end
`endif
endmodule
