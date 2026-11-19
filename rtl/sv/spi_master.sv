// spi_master.sv : SPI master, mode 0 (CPOL=0, CPHA=0), WIDTH-bit frames (SystemVerilog)
// Frame is clocked out MSB first; MISO is sampled on every rising SCLK edge.
module spi_master #(
  parameter int WIDTH = 16,
  parameter int HALF  = 4          // clk cycles per half SCLK period
) (
  input  logic             clk, rst,
  input  logic             start,       // pulse: begin a frame (ignored while busy)
  input  logic [WIDTH-1:0] tx_data,
  output logic             busy,
  output logic             done,        // 1-cycle pulse, rx_data valid
  output logic [WIDTH-1:0] rx_data,
  output logic             sclk, cs_n, mosi,
  input  logic             miso
);
  typedef enum logic [2:0] {IDLE, SETUP, HI, LO, HOLD} state_t;
  state_t state;
  localparam int CW = $clog2(HALF+1);
  localparam int BW = $clog2(WIDTH+1);
  localparam logic [CW-1:0] LAST_HALF = CW'(HALF-1);     // last cycle of a half period
  localparam logic [BW-1:0] LAST_BIT  = BW'(WIDTH-1);
  logic [CW-1:0] cnt;
  logic [BW-1:0] bitcnt;
  logic [WIDTH-1:0] tx_sh, rx_sh;

  assign busy = (state != IDLE);

  always_ff @(posedge clk) begin
    done <= 1'b0;
    if (rst) begin
      state <= IDLE; sclk <= 1'b0; cs_n <= 1'b1; mosi <= 1'b0;
      cnt <= '0; bitcnt <= '0; rx_data <= '0; tx_sh <= '0; rx_sh <= '0;
    end else begin
      unique case (state)
        IDLE: if (start) begin
          tx_sh <= tx_data; mosi <= tx_data[WIDTH-1]; cs_n <= 1'b0;
          cnt <= '0; state <= SETUP;
        end
        SETUP: if (cnt == LAST_HALF) begin            // chip-select setup time
          sclk <= 1'b1; rx_sh <= {rx_sh[WIDTH-2:0], miso};
          bitcnt <= '0; cnt <= '0; state <= HI;
        end else cnt <= cnt + 1'b1;
        HI: if (cnt == LAST_HALF) begin
          sclk <= 1'b0; cnt <= '0;
          if (bitcnt == LAST_BIT) state <= HOLD;
          else begin
            tx_sh <= {tx_sh[WIDTH-2:0], 1'b0};
            mosi  <= tx_sh[WIDTH-2];               // shift out on the falling edge
            state <= LO;
          end
        end else cnt <= cnt + 1'b1;
        LO: if (cnt == LAST_HALF) begin
          sclk <= 1'b1; rx_sh <= {rx_sh[WIDTH-2:0], miso};
          bitcnt <= bitcnt + 1'b1; cnt <= '0; state <= HI;
        end else cnt <= cnt + 1'b1;
        HOLD: if (cnt == LAST_HALF) begin
          cs_n <= 1'b1; done <= 1'b1; rx_data <= rx_sh; state <= IDLE; cnt <= '0;
        end else cnt <= cnt + 1'b1;
        default: state <= IDLE;
      endcase
    end
  end

`ifndef SYNTHESIS
  // ---- SystemVerilog assertions (checked in simulation, ignored in synthesis) ----
  // SCLK idles low whenever the slave is not selected (mode 0)
  a_idle_low  : assert property (@(posedge clk) disable iff (rst) cs_n |-> !sclk);
  // a finished frame releases chip select in the same cycle
  a_done_cs   : assert property (@(posedge clk) disable iff (rst) done |-> cs_n);
  // MOSI must not change while SCLK is high (the slave samples there)
  a_mosi_hold : assert property (@(posedge clk) disable iff (rst) (sclk && $past(sclk)) |-> $stable(mosi));
  // chip select is low for the whole frame
  a_busy_cs   : assert property (@(posedge clk) disable iff (rst) (state == SETUP || state == HI || state == LO) |-> !cs_n);
`endif
endmodule
