// 行为级 gold：16 个 16-bit signed 积求和，W=20，拍级切分与被测件相同
module VdotReduceK16Gold (
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
  wire signed [19:0] s =
    $signed(io_sum_wo_0) +
    $signed(io_sum_wo_1) +
    $signed(io_sum_wo_2) +
    $signed(io_sum_wo_3) +
    $signed(io_sum_wo_4) +
    $signed(io_sum_wo_5) +
    $signed(io_sum_wo_6) +
    $signed(io_sum_wo_7) +
    $signed(io_sum_wo_8) +
    $signed(io_sum_wo_9) +
    $signed(io_sum_wo_10) +
    $signed(io_sum_wo_11) +
    $signed(io_sum_wo_12) +
    $signed(io_sum_wo_13) +
    $signed(io_sum_wo_14) +
    $signed(io_sum_wo_15);
  reg  [127:0] io_vd_r;
  always @(posedge clock) begin
    if (io_fireS1) io_vd_r <= {96'h0, {12{s[19]}}, s};
  end
  assign io_vd = io_vd_r;
endmodule
