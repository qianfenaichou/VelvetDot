// ============================================================================
// VdotReduceK16Gen.sv
// 独立数据通路、同结构参数化、未集成进 VIMacU。
//
// 旁证件：K=16 走仓内生成器 CSA_Nto2With3to2MainPipeline 的退化调度（n∉{4,8} ⇒ 全 3:2，
// 5+3+2+1 = 11 实例 / 4 段），对应 §7.2「1,792 cells / 1.56 倍」那条【推算】。
// 仅作旁证，不进 base/ext 比值。
//
// 参数：K=16 lanes, SEW=8, W=2*SEW+floor(log2 K)=20 bits（位宽定理 L4）
// 树  ：仓内生成器退化调度（n∉{4,8} ⇒ 3:2），3 个 CSA4to2 + 8 个 CSA3to2，4 段
// 拍级：签名扩展 + 树 + W 位 CPA 全组合，单拍寄存器打在格式化后的 vd 上（同 K1 版
//       VdotReduce：io_vd_r <= {96'h0, sext32(cpa)}，fireS1 使能）
// 由 design/verify/area/gen_ext.py 生成，勿手改（改参数改脚本再重生成）。
// ============================================================================
`default_nettype none

module csa4to2_w20 (
  input  wire [19:0] a,
  input  wire [19:0] b,
  input  wire [19:0] c,
  input  wire [19:0] d,
  output wire [19:0] sum,
  output wire [19:0] car
);
  wire [19:0] cout_vec, sum_vec, carry_vec, sum_tmp, carry_tmp;
  assign cout_vec[0] = (a[0] ^ b[0]) ? c[0] : a[0];
  assign cout_vec[1] = (a[1] ^ b[1]) ? c[1] : a[1];
  assign cout_vec[2] = (a[2] ^ b[2]) ? c[2] : a[2];
  assign cout_vec[3] = (a[3] ^ b[3]) ? c[3] : a[3];
  assign cout_vec[4] = (a[4] ^ b[4]) ? c[4] : a[4];
  assign cout_vec[5] = (a[5] ^ b[5]) ? c[5] : a[5];
  assign cout_vec[6] = (a[6] ^ b[6]) ? c[6] : a[6];
  assign cout_vec[7] = (a[7] ^ b[7]) ? c[7] : a[7];
  assign cout_vec[8] = (a[8] ^ b[8]) ? c[8] : a[8];
  assign cout_vec[9] = (a[9] ^ b[9]) ? c[9] : a[9];
  assign cout_vec[10] = (a[10] ^ b[10]) ? c[10] : a[10];
  assign cout_vec[11] = (a[11] ^ b[11]) ? c[11] : a[11];
  assign cout_vec[12] = (a[12] ^ b[12]) ? c[12] : a[12];
  assign cout_vec[13] = (a[13] ^ b[13]) ? c[13] : a[13];
  assign cout_vec[14] = (a[14] ^ b[14]) ? c[14] : a[14];
  assign cout_vec[15] = (a[15] ^ b[15]) ? c[15] : a[15];
  assign cout_vec[16] = (a[16] ^ b[16]) ? c[16] : a[16];
  assign cout_vec[17] = (a[17] ^ b[17]) ? c[17] : a[17];
  assign cout_vec[18] = (a[18] ^ b[18]) ? c[18] : a[18];
  assign cout_vec[19] = (a[19] ^ b[19]) ? c[19] : a[19];
  assign sum_vec[0]   = a[0] ^ b[0] ^ c[0] ^ d[0];
  assign carry_vec[0] = (a[0] ^ b[0] ^ c[0] ^ d[0]) ? 1'b0 : d[0];
  assign sum_vec[1]   = a[1] ^ b[1] ^ c[1] ^ d[1] ^ cout_vec[0];
  assign carry_vec[1] = (a[1] ^ b[1] ^ c[1] ^ d[1]) ? cout_vec[0] : d[1];
  assign sum_vec[2]   = a[2] ^ b[2] ^ c[2] ^ d[2] ^ cout_vec[1];
  assign carry_vec[2] = (a[2] ^ b[2] ^ c[2] ^ d[2]) ? cout_vec[1] : d[2];
  assign sum_vec[3]   = a[3] ^ b[3] ^ c[3] ^ d[3] ^ cout_vec[2];
  assign carry_vec[3] = (a[3] ^ b[3] ^ c[3] ^ d[3]) ? cout_vec[2] : d[3];
  assign sum_vec[4]   = a[4] ^ b[4] ^ c[4] ^ d[4] ^ cout_vec[3];
  assign carry_vec[4] = (a[4] ^ b[4] ^ c[4] ^ d[4]) ? cout_vec[3] : d[4];
  assign sum_vec[5]   = a[5] ^ b[5] ^ c[5] ^ d[5] ^ cout_vec[4];
  assign carry_vec[5] = (a[5] ^ b[5] ^ c[5] ^ d[5]) ? cout_vec[4] : d[5];
  assign sum_vec[6]   = a[6] ^ b[6] ^ c[6] ^ d[6] ^ cout_vec[5];
  assign carry_vec[6] = (a[6] ^ b[6] ^ c[6] ^ d[6]) ? cout_vec[5] : d[6];
  assign sum_vec[7]   = a[7] ^ b[7] ^ c[7] ^ d[7] ^ cout_vec[6];
  assign carry_vec[7] = (a[7] ^ b[7] ^ c[7] ^ d[7]) ? cout_vec[6] : d[7];
  assign sum_vec[8]   = a[8] ^ b[8] ^ c[8] ^ d[8] ^ cout_vec[7];
  assign carry_vec[8] = (a[8] ^ b[8] ^ c[8] ^ d[8]) ? cout_vec[7] : d[8];
  assign sum_vec[9]   = a[9] ^ b[9] ^ c[9] ^ d[9] ^ cout_vec[8];
  assign carry_vec[9] = (a[9] ^ b[9] ^ c[9] ^ d[9]) ? cout_vec[8] : d[9];
  assign sum_vec[10]   = a[10] ^ b[10] ^ c[10] ^ d[10] ^ cout_vec[9];
  assign carry_vec[10] = (a[10] ^ b[10] ^ c[10] ^ d[10]) ? cout_vec[9] : d[10];
  assign sum_vec[11]   = a[11] ^ b[11] ^ c[11] ^ d[11] ^ cout_vec[10];
  assign carry_vec[11] = (a[11] ^ b[11] ^ c[11] ^ d[11]) ? cout_vec[10] : d[11];
  assign sum_vec[12]   = a[12] ^ b[12] ^ c[12] ^ d[12] ^ cout_vec[11];
  assign carry_vec[12] = (a[12] ^ b[12] ^ c[12] ^ d[12]) ? cout_vec[11] : d[12];
  assign sum_vec[13]   = a[13] ^ b[13] ^ c[13] ^ d[13] ^ cout_vec[12];
  assign carry_vec[13] = (a[13] ^ b[13] ^ c[13] ^ d[13]) ? cout_vec[12] : d[13];
  assign sum_vec[14]   = a[14] ^ b[14] ^ c[14] ^ d[14] ^ cout_vec[13];
  assign carry_vec[14] = (a[14] ^ b[14] ^ c[14] ^ d[14]) ? cout_vec[13] : d[14];
  assign sum_vec[15]   = a[15] ^ b[15] ^ c[15] ^ d[15] ^ cout_vec[14];
  assign carry_vec[15] = (a[15] ^ b[15] ^ c[15] ^ d[15]) ? cout_vec[14] : d[15];
  assign sum_vec[16]   = a[16] ^ b[16] ^ c[16] ^ d[16] ^ cout_vec[15];
  assign carry_vec[16] = (a[16] ^ b[16] ^ c[16] ^ d[16]) ? cout_vec[15] : d[16];
  assign sum_vec[17]   = a[17] ^ b[17] ^ c[17] ^ d[17] ^ cout_vec[16];
  assign carry_vec[17] = (a[17] ^ b[17] ^ c[17] ^ d[17]) ? cout_vec[16] : d[17];
  assign sum_vec[18]   = a[18] ^ b[18] ^ c[18] ^ d[18] ^ cout_vec[17];
  assign carry_vec[18] = (a[18] ^ b[18] ^ c[18] ^ d[18]) ? cout_vec[17] : d[18];
  assign sum_vec[19]   = a[19] ^ b[19] ^ c[19] ^ d[19] ^ cout_vec[18];
  assign carry_vec[19] = (a[19] ^ b[19] ^ c[19] ^ d[19]) ? cout_vec[18] : d[19];
  assign sum_tmp[0]   = sum_vec[0];
  assign carry_tmp[0] = 1'b0;
  assign sum_tmp[1]   = carry_vec[0];
  assign carry_tmp[1] = sum_vec[1];
  assign sum_tmp[2]   = sum_vec[2];
  assign carry_tmp[2] = carry_vec[1];
  assign sum_tmp[3]   = carry_vec[2];
  assign carry_tmp[3] = sum_vec[3];
  assign sum_tmp[4]   = sum_vec[4];
  assign carry_tmp[4] = carry_vec[3];
  assign sum_tmp[5]   = carry_vec[4];
  assign carry_tmp[5] = sum_vec[5];
  assign sum_tmp[6]   = sum_vec[6];
  assign carry_tmp[6] = carry_vec[5];
  assign sum_tmp[7]   = carry_vec[6];
  assign carry_tmp[7] = sum_vec[7];
  assign sum_tmp[8]   = sum_vec[8];
  assign carry_tmp[8] = carry_vec[7];
  assign sum_tmp[9]   = carry_vec[8];
  assign carry_tmp[9] = sum_vec[9];
  assign sum_tmp[10]   = sum_vec[10];
  assign carry_tmp[10] = carry_vec[9];
  assign sum_tmp[11]   = carry_vec[10];
  assign carry_tmp[11] = sum_vec[11];
  assign sum_tmp[12]   = sum_vec[12];
  assign carry_tmp[12] = carry_vec[11];
  assign sum_tmp[13]   = carry_vec[12];
  assign carry_tmp[13] = sum_vec[13];
  assign sum_tmp[14]   = sum_vec[14];
  assign carry_tmp[14] = carry_vec[13];
  assign sum_tmp[15]   = carry_vec[14];
  assign carry_tmp[15] = sum_vec[15];
  assign sum_tmp[16]   = sum_vec[16];
  assign carry_tmp[16] = carry_vec[15];
  assign sum_tmp[17]   = carry_vec[16];
  assign carry_tmp[17] = sum_vec[17];
  assign sum_tmp[18]   = sum_vec[18];
  assign carry_tmp[18] = carry_vec[17];
  assign sum_tmp[19]   = carry_vec[18];
  assign carry_tmp[19] = sum_vec[19];
  assign sum = sum_tmp;
  assign car = carry_tmp;
endmodule

module csa3to2_w20 (
  input  wire [19:0] a,
  input  wire [19:0] b,
  input  wire [19:0] c,
  output wire [19:0] sum,
  output wire [19:0] car
);
  wire [19:0] carry_hi = (a & b) | (a & c) | (b & c);
  assign sum = a ^ b ^ c;
  assign car = {carry_hi[18:0], 1'b0};
endmodule

module reduce_tree_k16 (
  input  wire [19:0] io_in_0,
  input  wire [19:0] io_in_1,
  input  wire [19:0] io_in_2,
  input  wire [19:0] io_in_3,
  input  wire [19:0] io_in_4,
  input  wire [19:0] io_in_5,
  input  wire [19:0] io_in_6,
  input  wire [19:0] io_in_7,
  input  wire [19:0] io_in_8,
  input  wire [19:0] io_in_9,
  input  wire [19:0] io_in_10,
  input  wire [19:0] io_in_11,
  input  wire [19:0] io_in_12,
  input  wire [19:0] io_in_13,
  input  wire [19:0] io_in_14,
  input  wire [19:0] io_in_15,
  output wire [19:0] io_out_sum,
  output wire [19:0] io_out_car
);

  // ---- stage 1 ----
  wire [19:0] w0, w1;
  csa3to2_w20 s0_csa3to2 (.a(io_in_0), .b(io_in_1), .c(io_in_2), .sum(w0), .car(w1));
  wire [19:0] w2, w3;
  csa3to2_w20 s1_csa3to2 (.a(io_in_3), .b(io_in_4), .c(io_in_5), .sum(w2), .car(w3));
  wire [19:0] w4, w5;
  csa3to2_w20 s2_csa3to2 (.a(io_in_6), .b(io_in_7), .c(io_in_8), .sum(w4), .car(w5));
  wire [19:0] w6, w7;
  csa3to2_w20 s3_csa3to2 (.a(io_in_9), .b(io_in_10), .c(io_in_11), .sum(w6), .car(w7));
  wire [19:0] w8, w9;
  csa3to2_w20 s4_csa3to2 (.a(io_in_12), .b(io_in_13), .c(io_in_14), .sum(w8), .car(w9));

  // ---- stage 2 ----
  wire [19:0] w10, w11;
  csa3to2_w20 s5_csa3to2 (.a(w0), .b(w1), .c(w2), .sum(w10), .car(w11));
  wire [19:0] w12, w13;
  csa3to2_w20 s6_csa3to2 (.a(w3), .b(w4), .c(w5), .sum(w12), .car(w13));
  wire [19:0] w14, w15;
  csa3to2_w20 s7_csa3to2 (.a(w6), .b(w7), .c(w8), .sum(w14), .car(w15));

  // ---- stage 3 ----
  wire [19:0] w16, w17;
  csa4to2_w20 s8_csa4to2 (.a(w10), .b(w11), .c(w12), .d(w13), .sum(w16), .car(w17));
  wire [19:0] w18, w19;
  csa4to2_w20 s9_csa4to2 (.a(w14), .b(w15), .c(w9), .d(io_in_15), .sum(w18), .car(w19));

  // ---- stage 4 ----
  wire [19:0] w20, w21;
  csa4to2_w20 s10_csa4to2 (.a(w16), .b(w17), .c(w18), .d(w19), .sum(w20), .car(w21));

  assign io_out_sum = w20;
  assign io_out_car = w21;
endmodule

module VdotReduceK16Gen (
  input  wire         clock,
  input  wire [15:0]  io_sum_wo_0,
  input  wire [15:0]  io_sum_wo_1,
  input  wire [15:0]  io_sum_wo_2,
  input  wire [15:0]  io_sum_wo_3,
  input  wire [15:0]  io_sum_wo_4,
  input  wire [15:0]  io_sum_wo_5,
  input  wire [15:0]  io_sum_wo_6,
  input  wire [15:0]  io_sum_wo_7,
  input  wire [15:0]  io_sum_wo_8,
  input  wire [15:0]  io_sum_wo_9,
  input  wire [15:0]  io_sum_wo_10,
  input  wire [15:0]  io_sum_wo_11,
  input  wire [15:0]  io_sum_wo_12,
  input  wire [15:0]  io_sum_wo_13,
  input  wire [15:0]  io_sum_wo_14,
  input  wire [15:0]  io_sum_wo_15,
  input  wire         io_fireS1,
  output wire [127:0] io_vd
);

  wire [19:0] op0 = {{4{io_sum_wo_0[15]}}, io_sum_wo_0};
  wire [19:0] op1 = {{4{io_sum_wo_1[15]}}, io_sum_wo_1};
  wire [19:0] op2 = {{4{io_sum_wo_2[15]}}, io_sum_wo_2};
  wire [19:0] op3 = {{4{io_sum_wo_3[15]}}, io_sum_wo_3};
  wire [19:0] op4 = {{4{io_sum_wo_4[15]}}, io_sum_wo_4};
  wire [19:0] op5 = {{4{io_sum_wo_5[15]}}, io_sum_wo_5};
  wire [19:0] op6 = {{4{io_sum_wo_6[15]}}, io_sum_wo_6};
  wire [19:0] op7 = {{4{io_sum_wo_7[15]}}, io_sum_wo_7};
  wire [19:0] op8 = {{4{io_sum_wo_8[15]}}, io_sum_wo_8};
  wire [19:0] op9 = {{4{io_sum_wo_9[15]}}, io_sum_wo_9};
  wire [19:0] op10 = {{4{io_sum_wo_10[15]}}, io_sum_wo_10};
  wire [19:0] op11 = {{4{io_sum_wo_11[15]}}, io_sum_wo_11};
  wire [19:0] op12 = {{4{io_sum_wo_12[15]}}, io_sum_wo_12};
  wire [19:0] op13 = {{4{io_sum_wo_13[15]}}, io_sum_wo_13};
  wire [19:0] op14 = {{4{io_sum_wo_14[15]}}, io_sum_wo_14};
  wire [19:0] op15 = {{4{io_sum_wo_15[15]}}, io_sum_wo_15};

  wire [19:0] tree_sum, tree_car;
  reduce_tree_k16 tree (.io_in_0(op0), .io_in_1(op1), .io_in_2(op2), .io_in_3(op3), .io_in_4(op4), .io_in_5(op5), .io_in_6(op6), .io_in_7(op7), .io_in_8(op8), .io_in_9(op9), .io_in_10(op10), .io_in_11(op11), .io_in_12(op12), .io_in_13(op13), .io_in_14(op14), .io_in_15(op15), .io_out_sum(tree_sum), .io_out_car(tree_car));

  // ---- 20 位 CPA + 单拍寄存器（同 K1 版 VdotReduce 的切分）----
  wire [19:0] cpa = tree_sum + tree_car;
  reg  [127:0] io_vd_r;
  always @(posedge clock) begin
    if (io_fireS1)
      io_vd_r <= {96'h0, {12{cpa[19]}}, cpa};
  end
  assign io_vd = io_vd_r;

endmodule

`default_nettype wire
