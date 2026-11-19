// byte_fifo.sv : small synchronous FIFO, first-word-fall-through read
module byte_fifo #(
  parameter int DEPTH_LOG2 = 4
) (
  input  logic       clk, rst,
  input  logic       push,
  input  logic [7:0] push_data,
  input  logic       pop,
  output logic [7:0] front,
  output logic       empty, full
);
  localparam int DEPTH = 1 << DEPTH_LOG2;
  logic [7:0] mem [DEPTH];
  logic [DEPTH_LOG2:0] wp, rp;
  assign empty = (wp == rp);
  assign full  = (wp[DEPTH_LOG2-1:0] == rp[DEPTH_LOG2-1:0]) && (wp[DEPTH_LOG2] != rp[DEPTH_LOG2]);
  assign front = mem[rp[DEPTH_LOG2-1:0]];
  always_ff @(posedge clk) begin
    if (rst) begin wp <= '0; rp <= '0; end
    else begin
      if (push && !full) begin mem[wp[DEPTH_LOG2-1:0]] <= push_data; wp <= wp + 1'b1; end
      if (pop && !empty) rp <= rp + 1'b1;
    end
  end
endmodule
