// 行为级 gold：8 个 16-bit signed 积求和，W=19，拍级切分与被测件相同
module VdotReduceK8Gold (
  input  wire         clock,
  input  wire [15:0]  io_sum_wo_0,
  input  wire [15:0]  io_sum_wo_1,
  input  wire [15:0]  io_sum_wo_2,
  input  wire [15:0]  io_sum_wo_3,
  input  wire [15:0]  io_sum_wo_4,
  input  wire [15:0]  io_sum_wo_5,
  input  wire [15:0]  io_sum_wo_6,
  input  wire [15:0]  io_sum_wo_7,
  input  wire         io_fireS1,
  output wire [127:0] io_vd
);
  wire signed [18:0] s =
    $signed(io_sum_wo_0) +
    $signed(io_sum_wo_1) +
    $signed(io_sum_wo_2) +
    $signed(io_sum_wo_3) +
    $signed(io_sum_wo_4) +
    $signed(io_sum_wo_5) +
    $signed(io_sum_wo_6) +
    $signed(io_sum_wo_7);
  reg  [127:0] io_vd_r;
  always @(posedge clock) begin
    if (io_fireS1) io_vd_r <= {96'h0, {13{s[18]}}, s};
  end
  assign io_vd = io_vd_r;
endmodule
