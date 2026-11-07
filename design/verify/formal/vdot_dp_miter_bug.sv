// 负控变异体（mutant）：金模型 lane3 改为零扩展 —— 50-formal-miter.sh --mutant 用这个文件，
// 期望输出 "model found: FAIL!"；若它也 SUCCESS，说明 miter 没有判别力（虚假通过）。
// vdot_dp_miter_bug.sv — **负控变异体**（由 vdot_dp_miter.sv 复制后注入 1 处缺陷）：
// 金模型 lane3 改为零扩展；DUT=VdotReduce vs 位级金模型，其余结构与其基件相同。
// 口径来自 design/ALGORITHM.md §3.5：只证数据通路等价，不覆盖流水/发射/旁路/异常。
//
// 金模型（算法 B）：每个 16 位积先做 **19 位符号扩展**，再两两相加并保持 19 位回绕，
// 最后 sext32 放到 vd[31:0]，高 96 位恒零。与 DUT 的 4:2 压缩树 + CPA 结构完全无关，
// 因此不是「用被测公式重算期望」（CODING-STD §5.1 的 tautological 禁令）。
//
// DUT（module VdotReduce）由 build/rtl/VdotReduce.sv 及其子模块闭包拼进同一文件，
// 拼接脚本见同目录 build_miter.sh。

module vdot_dp_spec(
  input  wire        clock,
  input  wire        io_fireS1,
  input  wire [15:0] io_sum_wo_0,
  input  wire [15:0] io_sum_wo_1,
  input  wire [15:0] io_sum_wo_2,
  input  wire [15:0] io_sum_wo_3,
  input  wire [15:0] io_sum_wo_4,
  input  wire [15:0] io_sum_wo_5,
  input  wire [15:0] io_sum_wo_6,
  input  wire [15:0] io_sum_wo_7,
  output reg  [127:0] io_vd
);
  // 19 位符号扩展（严禁零扩展）
  wire signed [18:0] s0 = {{3{io_sum_wo_0[15]}}, io_sum_wo_0};
  wire signed [18:0] s1 = {{3{io_sum_wo_1[15]}}, io_sum_wo_1};
  wire signed [18:0] s2 = {{3{io_sum_wo_2[15]}}, io_sum_wo_2};
  wire signed [18:0] s3 = {3'b000, io_sum_wo_3}; // MUTANT: lane3 零扩展（应判 FAIL）
  wire signed [18:0] s4 = {{3{io_sum_wo_4[15]}}, io_sum_wo_4};
  wire signed [18:0] s5 = {{3{io_sum_wo_5[15]}}, io_sum_wo_5};
  wire signed [18:0] s6 = {{3{io_sum_wo_6[15]}}, io_sum_wo_6};
  wire signed [18:0] s7 = {{3{io_sum_wo_7[15]}}, io_sum_wo_7};

  // 逐项 int 累加（19 位回绕，与结构无关的顺序：先配对再合并）
  wire signed [18:0] p01 = s0 + s1;
  wire signed [18:0] p23 = s2 + s3;
  wire signed [18:0] p45 = s4 + s5;
  wire signed [18:0] p67 = s6 + s7;
  wire signed [18:0] q0   = p01 + p23;
  wire signed [18:0] q1   = p45 + p67;
  wire signed [18:0] S    = q0 + q1;

  wire [31:0] S32 = {{13{S[18]}}, S};   // sext32
  wire [127:0] formatted = {96'b0, S32}; // vd[127:32] 恒零

  always @(posedge clock) begin
    if (io_fireS1) io_vd <= formatted;
  end
endmodule

module vdot_dp_miter_bug(
  input wire        clock,
  input wire        io_fireS1,
  input wire [15:0] io_sum_wo_0,
  input wire [15:0] io_sum_wo_1,
  input wire [15:0] io_sum_wo_2,
  input wire [15:0] io_sum_wo_3,
  input wire [15:0] io_sum_wo_4,
  input wire [15:0] io_sum_wo_5,
  input wire [15:0] io_sum_wo_6,
  input wire [15:0] io_sum_wo_7
);
  wire [127:0] vd_dut;
  wire [127:0] vd_ref;

  VdotReduce u_dut (
    .clock       (clock),
    .io_fireS1   (io_fireS1),
    .io_sum_wo_0 (io_sum_wo_0),
    .io_sum_wo_1 (io_sum_wo_1),
    .io_sum_wo_2 (io_sum_wo_2),
    .io_sum_wo_3 (io_sum_wo_3),
    .io_sum_wo_4 (io_sum_wo_4),
    .io_sum_wo_5 (io_sum_wo_5),
    .io_sum_wo_6 (io_sum_wo_6),
    .io_sum_wo_7 (io_sum_wo_7),
    .io_vd       (vd_dut)
  );

  vdot_dp_spec u_ref (
    .clock       (clock),
    .io_fireS1   (io_fireS1),
    .io_sum_wo_0 (io_sum_wo_0),
    .io_sum_wo_1 (io_sum_wo_1),
    .io_sum_wo_2 (io_sum_wo_2),
    .io_sum_wo_3 (io_sum_wo_3),
    .io_sum_wo_4 (io_sum_wo_4),
    .io_sum_wo_5 (io_sum_wo_5),
    .io_sum_wo_6 (io_sum_wo_6),
    .io_sum_wo_7 (io_sum_wo_7),
    .io_vd       (vd_ref)
  );

  // 断言：一拍后 DUT 与金模型逐位相等（含高 96 位恒零）
  always @(posedge clock) assert (vd_dut == vd_ref);
endmodule
