// 金模型（算法 B）两份：vdot_dp_spec（正确）与 vdot_dp_spec_bug（负控：lane3 零扩展）。
// 用法：core-package/scripts/50-formal-miter.sh（内部用 yosys `miter -equiv` + `sat`，见同目录 run_sat 注释）
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
  wire signed [18:0] s3 = {{3{io_sum_wo_3[15]}}, io_sum_wo_3};
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

module vdot_dp_spec_bug(
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

