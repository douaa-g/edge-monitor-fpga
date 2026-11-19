// packetizer.sv : turns processed samples into UART packets
//   RAW=1 : [A5, hi, lo]                         every sample (reference "send everything" mode)
//   RAW=0 : event  [C7, idxH, idxL, ewH, ewL, flags]  on a rising alarm
//           summary[B6, idxH, idxL, ewH, ewL, flags]  every 2**SUMMARY_LOG2 samples
module packetizer #(
  parameter bit RAW = 1'b0,
  parameter int SUMMARY_LOG2 = 6
) (
  input  logic        clk, rst,
  input  logic        in_valid,
  input  logic [11:0] in_sample, in_ewma,
  input  logic [15:0] in_idx,
  input  logic        in_ap, in_an,
  output logic        push,
  output logic [7:0]  push_data,
  input  logic        fifo_full,
  output logic        overflow          // sticky: a byte was dropped (must stay 0)
);
  logic [7:0] pbuf [12];
  logic [3:0] len, pos;
  logic       prev_alarm;
  logic [7:0] flags;
  logic       alarm_now;
  logic [3:0] n;                  // number of bytes queued for this sample (temporary)

  assign flags     = {6'b0, in_an, in_ap};
  assign alarm_now = in_ap | in_an;

  always_ff @(posedge clk) begin
    push <= 1'b0;
    if (rst) begin
      len <= '0; pos <= '0; prev_alarm <= 1'b0; overflow <= 1'b0; push_data <= '0;
    end else begin
      if (in_valid) begin
        n = 4'd0;
        if (RAW) begin
          pbuf[0] <= 8'hA5; pbuf[1] <= {4'b0, in_sample[11:8]}; pbuf[2] <= in_sample[7:0];
          n = 4'd3;
        end else begin
          if (alarm_now && !prev_alarm) begin
            pbuf[0] <= 8'hC7; pbuf[1] <= in_idx[15:8]; pbuf[2] <= in_idx[7:0];
            pbuf[3] <= {4'b0, in_ewma[11:8]}; pbuf[4] <= in_ewma[7:0]; pbuf[5] <= flags;
            n = 4'd6;
          end
          if (in_idx[SUMMARY_LOG2-1:0] == {SUMMARY_LOG2{1'b1}}) begin
            pbuf[n+0] <= 8'hB6; pbuf[n+1] <= in_idx[15:8]; pbuf[n+2] <= in_idx[7:0];
            pbuf[n+3] <= {4'b0, in_ewma[11:8]}; pbuf[n+4] <= in_ewma[7:0]; pbuf[n+5] <= flags;
            n = n + 4'd6;
          end
        end
        prev_alarm <= alarm_now;
        len <= n; pos <= '0;
      end else if (pos != len) begin             // stream the buffered packet(s), one byte/clock
        if (fifo_full) overflow <= 1'b1;
        else begin push <= 1'b1; push_data <= pbuf[pos]; end
        pos <= pos + 1'b1;
      end
    end
  end
endmodule
