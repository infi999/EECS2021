module yMux1(z, a, b, c);
   output z;
   input  a, b, c;
   wire   notC, upper, lower;

   not my_not(notC, c);
   and upperAnd(upper, a, notC);
   and lowerAnd(lower, c, b);
   or my_or(z, upper, lower);
endmodule // yMux1

module yMux(z, a, b, c);
   parameter SIZE = 2;
   output [SIZE-1:0] z;
   input  [SIZE-1:0] a, b;
   input  c;

   yMux1 mine[SIZE-1:0](z, a, b, c);
endmodule // yMux

module yMux4to1(z, a0, a1, a2, a3, c);
   parameter SIZE = 2;
   output [SIZE-1:0] z;
   input  [SIZE-1:0] a0, a1, a2, a3;
   input  [1:0] c;
   wire   [SIZE-1:0] zLo, zHi;

   yMux #(SIZE) lo(zLo, a0, a1, c[0]);
   yMux #(SIZE) hi(zHi, a2, a3, c[0]);
   yMux #(SIZE) final(z, zLo, zHi, c[1]);
endmodule // yMux4to1

module yAdder1 (z, cout, a, b, cin) ;
   output z, cout;
   input  a, b, cin;

   xor left_xor(tmp, a, b);
   xor right_xor(z, cin, tmp);
   and left_and(outL, a, b);
   and right_and(outR, tmp, cin);
   or my_or(cout, outR, outL);
endmodule // yAdder1

module yAdder (z, cout, a, b, cin) ;
   output [31:0] z;
   output        cout;
   input  [31:0] a, b;
   input         cin;
   wire   [31:0] in, out;

   yAdder1 mine [31:0] (z, out, a, b, in);

   assign in[0] = cin;

   genvar        i;
   generate
      for (i = 1; i < 32; i = i + 1) begin : asg
         assign in[i] = out[i-1];
      end
   endgenerate

   assign cout = out[31];
endmodule // yAdder

module yArith (z, cout, a, b, ctrl) ;
   // add if ctrl=0, subtract if ctrl=1
   output [31:0] z;
   output cout;
   input  [31:0] a, b;
   input  ctrl;
   wire   [31:0] notB, tmp;
   wire   cin;

   // instantiate the components and connect them
   assign cin = ctrl;
   not my_not [31:0] (notB, b);
   yMux #(32) mux(tmp, b, notB, cin);
   yAdder adder(z, cout, a, tmp, cin);
endmodule // yArith

module yAlu (z, ex, a, b, op) ;
   input [31:0] a, b;
   input [2:0]  op;
   output [31:0] z;
   output        ex;
   wire          cout;
   wire [31:0]   alu_and, alu_or, alu_arith, slt, tmp;

   wire [15:0]   z16;
   wire [7:0]    z8;
   wire [3:0]    z4;
   wire [1:0]    z2;
   wire          z1, z0;

   // upper bits are always zero
   assign slt[31:1] = 0;

   // ex ('or' all bits of z, then 'not' the result)
   or or16[15:0] (z16, z[15: 0], z[31:16]);
   or or8[7:0] (z8, z16[7: 0], z16[15:8]);
   or or4[3:0] (z4, z8[3: 0], z8[7:4]);
   or or2[1:0] (z2, z4[1:0], z4[3:2]);
   or or1[15:0] (z1, z2[1], z2[0]);
   not m_not (z0, z1);
   assign ex = z0;

   // set slt[0]
   xor (condition, a[31], b[31]);
   yArith slt_arith (tmp, cout, a, b, 1);
   yMux #(.SIZE(1)) slt_mux(slt[0], tmp[31], a[31], condition);

   // instantiate the components and connect them
   and m_and [31:0] (alu_and, a, b);
   or m_or [31:0] (alu_or, a, b);
   yArith m_arith (alu_arith, cout, a, b, op[2]);
   yMux4to1 #(.SIZE(32)) mux(z, alu_and, alu_or, alu_arith, slt, op[1:0]);
endmodule // yAlu

module yIF (ins, PCp4, PCin, clk) ;
   output [31:0] ins, PCp4;
   input  [31:0] PCin;
   input  clk;
   wire   [31:0] pcRegOut;
   wire   ex;
   reg    [31:0] memIn = 0;

   register #(32) pcReg(pcRegOut, PCin, clk, 1);
   yAlu alu(PCp4, ex, 4, pcRegOut, 3'b010);
   mem memory(ins, pcRegOut, memIn, clk, 1, 0);
endmodule // yIF

module yID (rd1, rd2, imm, jTarget, ins, wd, RegDst, RegWrite, clk) ;
   output [31:0] rd1, rd2, imm;
   output [25:0] jTarget;
   input [31:0]  ins, wd;
   input         RegDst, RegWrite, clk;
   wire   [4:0] rn1, rn2, wn;
   wire [15:0]   zeros, ones;
   assign zeros[15:0] = 16'b0000000000000000;
   assign ones[15:0] = 16'b1111111111111111;

   assign rn1 = ins[25:21];
   assign rn2 = ins[20:16];
   yMux #(5) mux(wn, rn2, ins[15:11], RegDst);

   assign imm[15:0] = ins[15:0];
   yMux #(16) se(imm[31:16], zeros, ones, ins[15]);

   assign jTarget = ins[25:0];

   rf regfile(rd1, rd2, rn1, rn2, wn, wd, clk, RegWrite);
endmodule // yID

module yEX (z, zero, rd1, rd2, imm, op, ALUSrc) ;
   output [31:0] z;
   output        zero;
   input [31:0]  rd1, rd2, imm;
   input  [2:0] op;
   input  ALUSrc;
   wire   [31:0] b;

   yMux #(32) mux(b, rd2, imm, ALUSrc);
   yAlu alu(z, zero, rd1, b, op);
endmodule // yEX

module yDM(memOut, exeOut, rd2, clk, MemRead, MemWrite) ;
   output [31:0] memOut;
   input [31:0]  exeOut, rd2;
   input         clk, MemRead, MemWrite;

   mem memory(memOut, exeOut, rd2, clk, MemRead, MemWrite);
endmodule // yDM

module yWB(wb, exeOut, memOut, Mem2Reg) ;
   output [31:0] wb;
   input [31:0]  exeOut, memOut;
   input         Mem2Reg;

   yMux #(32) mux(wb, exeOut, memOut, Mem2Reg);
endmodule // yWB

module yPC(PCin, PCp4, INT, entryPoint, imm, jTarget, zero, branch,
jump);
// select instruction location for branch, jump, entry or continue.
output [31:0] PCin;
input [31:0] PCp4, entryPoint, imm;
input [25:0] jTarget;
input INT, zero, branch, jump;
wire [31:0] immX4, bTarget, choiceA, choiceB, jAddress;
wire doBranch, zf;
assign immX4[31:2] = imm[29:0]; // imm * 4
assign immX4[1:0] = 2'b00;
assign jAddress[31:28] = PCp4[31:28];
assign jAddress[27:2] = jTarget[25:0]; // 26-bit jTarget * 4
assign jAddress[1:0] = 2'b00;
yAlu myALU(bTarget, zf, PCp4, immX4, 3'b010);
and (doBranch, branch, zero);
yMux #(32) mux1(choiceA, PCp4, bTarget, doBranch); // continue or branch
yMux #(32) mux2(choiceB, choiceA, jAddress, jump); // or jump
yMux #(32) mux3(PCin, choiceB, entryPoint, INT); // or entry
endmodule

module yC1(rType, lw, sw, jump, branch, opCode);
// auto generate control signals from opCode
output rType, lw, sw, jump, branch;
input [5:0] opCode;
wire not5, not4, not3, not2, not1, not0;
not (not5, opCode[5]);
not (not4, opCode[4]);
not (not3, opCode[3]);
not (not2, opCode[2]);
not (not1, opCode[1]);
not (not0, opCode[0]);
// below is corresponding minTerms in the table
and (rType, not5, not4, not3, not2, not1, not0);
and (jump, not5, not4, not3, not2, opCode[1], not0);
and (lw, opCode[5], not4, not3, not2, opCode[1], opCode[0]);
and (sw, opCode[5], not4, opCode[3], not2, not1, opCode[0]);
and (branch, not5, not4, not3, opCode[2], not1, not0);
endmodule

module yC2(RegDst, AluSrc, RegWrite, Mem2Reg, MemRead,
MemWrite, rType, lw, sw, branch);
output RegDst, AluSrc, RegWrite, Mem2Reg, MemRead,
MemWrite;
input rType, lw, sw, branch;
assign RegDst = rType;
nor (AluSrc, rType, branch);
nor (RegWrite, sw, branch);
assign Mem2Reg = lw;
assign MemRead = lw;
assign MemWrite = sw;
endmodule

module yC3(ALUop, rType,
branch);
output [1:0] ALUop;
input rType, branch;
ALUop[0] = branch;
ALUop[1] = rType;
endmodule

module yC4(op, ALUop, fnCode);
output [2:0] op;
input [1:0] ALUop;
input [5:0] fnCode;
wire f0ORf3, f2ANDA1, f1ANDA1;
or (f0ORf3, fnCode[0], fnCode[3]);
and (op[0], f0ORf3, ALUop[1]);
and (f2ANDA1, fnCode[2], ALUop[1]);
not (op[1], f2ANDA1);
and (f1ANDA1, fnCode[1], ALUop[1]);
or (op[2], f1ANDA1, ALUop[0]);
endmodule

module yChip(ins, rd2, wb, entryPoint, INT, clk);
output [31:0] ins, rd2, wb;
input [31:0] entryPoint;
input INT, clk;
//-------------------------------------copy from labN3 start
wire RegDst, RegWrite, AluSrc, Mem2Reg, MemRead, MemWrite,
jump, branch;
wire [1:0] ALUop;
wire [2:0] op;
wire [5:0] opCode, fnCode;
wire [31:0] wd, rd1, imm, PCp4, z, memOut, PCin;
wire [25:0] jTarget;
wire zero;
yIF myIF(ins, PCp4, PCin, clk);
yID myID(rd1, rd2, imm, jTarget, ins, wd, RegDst, RegWrite,
clk);
yEX myEX(z, zero, rd1, rd2, imm, op, AluSrc);
yDM myDM(memOut, z, rd2, clk, MemRead, MemWrite);
yWB myWB(wb, z, memOut, Mem2Reg);
assign wd = wb;
yPC myPC(PCin, PCp4, INT, entryPoint, imm, jTarget, zero,
branch, jump);
assign opCode = ins[31:26];
yC1 myC1(rType, lw, sw, jump, branch, opCode);
yC2 myC2(RegDst, AluSrc, RegWrite, Mem2Reg, MemRead,
MemWrite, rType, lw, sw, branch);
assign fnCode = ins[5:0];
yC3 myC3(ALUop, rType, branch);
yC4 myC4(op, ALUop, fnCode);
//-------------------------------------copy from labN3 end
endmodule

