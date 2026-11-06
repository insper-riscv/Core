// Properties of alu (combinational), checked on the Verilog netlist GHDL synthesizes.
// The model is the RV32I computational semantics written the plain way, with the operators of the language and
// no staging: the sum and the difference, the signed and unsigned comparisons, the three shifts by the low five
// bits of operand B, the bitwise operations, LUI, JALR (the sum with bit 0 cleared) and the six branch
// conditions. The ALU under proof has one shared adder, shifters in stages of radix 4 and a one-hot AND-OR
// result, so each property is an equivalence between that structure and the plain operator.
// The operation codes are the ones the decoder hands to the EX stage, and the one-hot result selection is the
// one alu_result_select produces for each of them (the decoder fixes the pair, the ALU never sees another).
module props (input clk);
  (* anyseq *) wire [4:0] op;
  (* anyseq *) wire [31:0] a, b;
  reg  [7:0] sel;
  wire [31:0] d; wire branch;

  localparam ALU_ADD  = 5'b00000, ALU_SLL  = 5'b00001, ALU_XOR  = 5'b00100, ALU_SRL  = 5'b00101,
             ALU_OR   = 5'b00110, ALU_AND  = 5'b00111, ALU_SUB  = 5'b01000, ALU_SLT  = 5'b01010,
             ALU_SLTU = 5'b01011, ALU_SRA  = 5'b01101, ALU_JALR = 5'b10000, ALU_LUI  = 5'b10001,
             ALU_BEQ  = 5'b11000, ALU_BNE  = 5'b11001, ALU_BLT  = 5'b11100, ALU_BGE  = 5'b11101,
             ALU_BLTU = 5'b11110, ALU_BGEU = 5'b11111;

  // The one-hot selection of alu_result_select: bit 0 sum, 1 SLL, 2 SLT, 3 SLTU, 4 XOR, 5 right shift, 6 OR, 7 AND.
  // JALR and LUI select the sum, a branch selects nothing.
  always @(*) begin
    if (op[4]) sel = op[3] ? 8'h00 : 8'h01;
    else       sel = 8'h01 << op[2:0];
  end

  alu dut (.i_op(op), .i_res_sel(sel), .i_a(a), .i_b(b), .o_d(d), .o_branch(branch));

  wire valid = op == ALU_ADD  || op == ALU_SLL  || op == ALU_XOR  || op == ALU_SRL  || op == ALU_OR   ||
               op == ALU_AND  || op == ALU_SUB  || op == ALU_SLT  || op == ALU_SLTU || op == ALU_SRA  ||
               op == ALU_JALR || op == ALU_LUI  || op == ALU_BEQ  || op == ALU_BNE  || op == ALU_BLT  ||
               op == ALU_BGE  || op == ALU_BLTU || op == ALU_BGEU;

  wire [4:0]  shamt = b[4:0];
  wire signed [31:0] sa = a, sb = b;

  // The data result of the plain model; a branch gives zero.
  reg [31:0] ref_d;
  always @(*) begin
    case (op)
      ALU_ADD:  ref_d = a + b;
      ALU_SUB:  ref_d = a - b;
      ALU_SLL:  ref_d = a << shamt;
      ALU_SRL:  ref_d = a >> shamt;
      ALU_SRA:  ref_d = sa >>> shamt;
      ALU_XOR:  ref_d = a ^ b;
      ALU_OR:   ref_d = a | b;
      ALU_AND:  ref_d = a & b;
      ALU_SLT:  ref_d = {31'h0, sa < sb};
      ALU_SLTU: ref_d = {31'h0, a < b};
      ALU_JALR: ref_d = (a + b) & 32'hFFFFFFFE;
      ALU_LUI:  ref_d = b;
      default:  ref_d = 32'h0;
    endcase
  end

  // The branch flag of the plain model; only a branch operation can set it.
  reg ref_branch;
  always @(*) begin
    case (op)
      ALU_BEQ:  ref_branch = a == b;
      ALU_BNE:  ref_branch = a != b;
      ALU_BLT:  ref_branch = sa < sb;
      ALU_BGE:  ref_branch = sa >= sb;
      ALU_BLTU: ref_branch = a < b;
      ALU_BGEU: ref_branch = a >= b;
      default:  ref_branch = 1'b0;
    endcase
  end

  always @(*) begin
    assume (valid);
    // 1. The data result is the one of the plain operator, for every operation and every pair of operands.
    assert (d == ref_d);
    // 2. The branch flag is the condition of the branch, and zero for every other operation.
    assert (branch == ref_branch);
    // 3. The right shifts agree with each other on the amount: a logical shift of a value with the sign bit clear
    //    is the arithmetic one (the fill bit only matters when the sign is set).
    if (op == ALU_SRL && !a[31]) assert (d == (sa >>> shamt));
    // 4. JALR never sets bit 0, and the other sums keep the bit of the adder.
    if (op == ALU_JALR) assert (!d[0]);
    // 5. A branch writes nothing: the data result is zero.
    if (op[4] && op[3]) assert (d == 32'h0);
  end

`ifdef COVER
  always @(*) begin
    cover (op == ALU_SRA && a[31] && shamt == 5'd31);
    cover (op == ALU_SRL && a[31] && shamt == 5'd17);
    cover (op == ALU_SLL && shamt == 5'd1 && a != 32'h0);
    cover (op == ALU_SLT && sa < sb && a[31] != b[31]);
    cover (op == ALU_SLTU && a < b && a[31] != b[31]);
    cover (op == ALU_JALR && (a + b) != ((a + b) & 32'hFFFFFFFE));
    cover (op == ALU_BGEU && branch && a == b);
    cover (op == ALU_BLT && branch);
    cover (op == ALU_BEQ && !branch);
  end
`endif
endmodule
