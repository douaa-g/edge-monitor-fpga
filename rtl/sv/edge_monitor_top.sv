// edge_monitor_top.sv : top level of the condition-monitoring brick
//
//   SPI ADC --> [spi_master (SV)] --> [ewma_cusum (VHDL)] --> [packetizer (SV)]
//                                                              --> [byte_fifo (SV)] --> [uart_tx (VHDL)] --> host
//
// The two VHDL blocks are instantiated from SystemVerilog; the synthesis flow
// (synth/synth.sh) elaborates them with the GHDL plugin for Yosys.
module edge_monitor_top #(
  parameter int SAMPLE_DIV = 12000,   // clk cycles per sample (12 MHz / 12000 = 1 kHz)
  parameter int SPI_HALF   = 4,       // SCLK = clk / (2*SPI_HALF) = 1.5 MHz at 12 MHz
  parameter bit RAW        = 1'b0     // 1: stream every sample, 0: summaries + alarm events
) (
  input  logic clk, rst,
  // SPI ADC (12-bit result in the low bits of a 16-bit frame)
  output logic adc_sclk, adc_cs_n, adc_mosi,
  input  logic adc_miso,
  // host link and status
  output logic uart_tx_pin,
  output logic alarm_led,
  output logic fifo_overflow
);
  // ---------------- sample timer + SPI acquisition ----------------
  logic [$clog2(SAMPLE_DIV)-1:0] tick_cnt;
  logic start, spi_busy, spi_done;
  logic [15:0] spi_rx;

  always_ff @(posedge clk) begin
    start <= 1'b0;
    if (rst) tick_cnt <= '0;
    else if (tick_cnt == SAMPLE_DIV-1) begin tick_cnt <= '0; start <= 1'b1; end
    else tick_cnt <= tick_cnt + 1'b1;
  end

  spi_master #(.WIDTH(16), .HALF(SPI_HALF)) u_spi (
    .clk, .rst, .start, .tx_data(16'h0000), .busy(spi_busy), .done(spi_done), .rx_data(spi_rx),
    .sclk(adc_sclk), .cs_n(adc_cs_n), .mosi(adc_mosi), .miso(adc_miso));

  // ---------------- drift detector (VHDL) ----------------
  logic [11:0] sample_hold, ewma;
  logic        core_valid, ap, an;
  logic [15:0] sample_idx;

  always_ff @(posedge clk) begin
    if (rst) begin sample_hold <= '0; sample_idx <= '0; end
    else begin
      if (spi_done)  sample_hold <= spi_rx[11:0];
      if (core_valid) sample_idx <= sample_idx + 1'b1;
    end
  end

  ewma_cusum u_core (
    .clk, .rst, .s_valid(spi_done), .s_data(spi_rx[11:0]),
    .o_valid(core_valid), .o_ewma(ewma), .o_alarm_pos(ap), .o_alarm_neg(an));

  // ---------------- packets -> FIFO -> UART (VHDL) ----------------
  logic       push, ff_full, ff_empty, ff_pop, tx_ready, tx_valid;
  logic [7:0] push_data, ff_front;

  packetizer #(.RAW(RAW), .SUMMARY_LOG2(6)) u_pkt (
    .clk, .rst, .in_valid(core_valid), .in_sample(sample_hold), .in_ewma(ewma),
    .in_idx(sample_idx), .in_ap(ap), .in_an(an),
    .push, .push_data, .fifo_full(ff_full), .overflow(fifo_overflow));

  byte_fifo #(.DEPTH_LOG2(4)) u_fifo (
    .clk, .rst, .push, .push_data, .pop(ff_pop), .front(ff_front), .empty(ff_empty), .full(ff_full));

  assign tx_valid = !ff_empty && tx_ready;
  assign ff_pop   = tx_valid;

  uart_tx u_uart (.clk, .rst, .valid(tx_valid), .data(ff_front), .ready(tx_ready), .tx(uart_tx_pin));

  assign alarm_led = ap | an;
endmodule
