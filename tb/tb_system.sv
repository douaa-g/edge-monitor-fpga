// System testbench for the full brick (run on the Yosys-synthesised mixed VHDL/SV netlist).
// ADC model feeds samples from a hex file; a UART receiver captures every byte the
// brick transmits and dumps it to a file for comparison with the Python model.
`timescale 1ns/1ps
module tb_system;
  localparam int SAMPLE_DIV = 600;   // must match the netlist configuration (synth/synth.sh sim)
  localparam int CPB        = 16;
  string stim_file, out_file;
  int n_samples;

  logic clk = 0, rst = 1;
  logic adc_sclk, adc_cs_n, adc_mosi, adc_miso = 0;
  logic uart_tx_pin, alarm_led, fifo_overflow;
  always #5 clk = ~clk;

  edge_monitor_top dut (.clk, .rst, .adc_sclk, .adc_cs_n, .adc_mosi, .adc_miso,
                        .uart_tx_pin, .alarm_led, .fifo_overflow);

  // ---------------- ADC model (12-bit result in a 16-bit frame, mode 0) ----------------
  logic [11:0] stim [0:16383];     // up to 16384 samples
  logic [15:0] adc_sh;
  int frame = 0;
  always @(negedge adc_cs_n) begin
    adc_sh = {4'b0, (frame < n_samples) ? stim[frame] : 12'h000};
    adc_miso = adc_sh[15];
    frame++;
  end
  always @(negedge adc_sclk) if (!adc_cs_n) begin adc_sh = {adc_sh[14:0], 1'b0}; adc_miso = adc_sh[15]; end

  // ---------------- UART receiver ----------------
  int fd, nbytes = 0;
  logic [7:0] rb;
  initial begin
    forever begin
      @(negedge uart_tx_pin);
      if (!rst) begin
        #(CPB * 10 / 2);
        for (int i = 0; i < 8; i++) begin #(CPB * 10); rb[i] = uart_tx_pin; end
        #(CPB * 10);
        if (uart_tx_pin !== 1'b1) $display("UART framing error at byte %0d", nbytes);
        $fdisplay(fd, "%02x", rb);
        nbytes++;
      end
    end
  end

  int ovf = 0, alarm_cycles = 0;
  always @(posedge clk) begin
    if (fifo_overflow) ovf++;
    if (alarm_led) alarm_cycles++;
  end

  initial begin
    if (!$value$plusargs("STIM=%s", stim_file)) stim_file = "results/stim.hex";
    if (!$value$plusargs("OUT=%s", out_file))   out_file  = "build/rtl_out.hex";
    if (!$value$plusargs("N=%d", n_samples))    n_samples = 1000;
    $readmemh(stim_file, stim);
    fd = $fopen(out_file, "w");
    repeat (10) @(posedge clk); rst = 0;
    repeat ((n_samples + 2) * SAMPLE_DIV + 40 * CPB * 10) @(posedge clk);
    $fclose(fd);
    $display("system: %0d samples, %0d UART bytes, fifo overflow cycles=%0d, alarm cycles=%0d",
             n_samples, nbytes, ovf, alarm_cycles);
    $finish;
  end
endmodule
