// Self-checking testbench for spi_master: behavioural 12-bit ADC slave (mode 0),
// random samples, frame-length / data checks, assertions enabled (rtl/sv/spi_master.sv).
`timescale 1ns/1ps
module tb_spi_master;
  localparam int HALF = 4;
  logic clk = 0, rst = 1, start = 0, miso;
  logic [15:0] rx_data;
  logic busy, done, sclk, cs_n, mosi;
  always #5 clk = ~clk;

  spi_master #(.WIDTH(16), .HALF(HALF)) dut (
    .clk, .rst, .start, .tx_data(16'hA5C3), .busy, .done, .rx_data, .sclk, .cs_n, .mosi, .miso);

  // ---- ADC model: loads {4'b0, sample} when CS falls, shifts on SCLK falling edges ----
  logic [11:0] sample;
  logic [15:0] adc_sh;
  logic [15:0] mosi_seen;
  always @(negedge cs_n) begin adc_sh = {4'b0, sample}; miso = adc_sh[15]; end
  always @(negedge sclk) if (!cs_n) begin adc_sh = {adc_sh[14:0], 1'b0}; miso = adc_sh[15]; end
  always @(posedge sclk) mosi_seen = {mosi_seen[14:0], mosi};

  int rises, frames, errors, n_zero, n_max;
  always @(posedge sclk) rises++;

  initial begin
    sample = 0; miso = 0; rises = 0; frames = 0; errors = 0; n_zero = 0; n_max = 0;
    repeat (5) @(posedge clk); rst = 0; repeat (3) @(posedge clk);
    for (int i = 0; i < 3000; i++) begin
      case (i)
        0: sample = 12'h000;           // corner cases first
        1: sample = 12'hFFF;
        2: sample = 12'h800;
        3: sample = 12'h001;
        default: sample = 12'($urandom);
      endcase
      rises = 0;
      @(posedge clk); start <= 1; @(posedge clk); start <= 0;
      @(posedge done);
      @(posedge clk);
      frames++;
      if (rx_data !== {4'b0, sample}) begin
        errors++;
        if (errors < 5) $display("MISMATCH frame %0d: got %h expected %h", i, rx_data, {4'b0, sample});
      end
      if (rises !== 16) begin errors++; $display("frame %0d: %0d SCLK edges (expected 16)", i, rises); end
      if (mosi_seen !== 16'hA5C3) begin errors++; $display("frame %0d: MOSI %h", i, mosi_seen); end
      if (sample == 12'h000) n_zero++;
      if (sample == 12'hFFF) n_max++;
      repeat ($urandom_range(0, 6)) @(posedge clk);   // random gap between frames
    end
    $display("spi_master: %0d frames, %0d errors (min-code seen %0d x, max-code seen %0d x)",
             frames, errors, n_zero, n_max);
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED");
    $finish;
  end
endmodule
