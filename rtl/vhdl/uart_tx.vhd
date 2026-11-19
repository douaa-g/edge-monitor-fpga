-- uart_tx.vhd : 8N1 UART transmitter (VHDL-2008)
-- valid/ready handshake: a byte is accepted when valid='1' and ready='1'.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_tx is
  generic (CLKS_PER_BIT : positive := 104);   -- 12 MHz / 115200 baud
  port (
    clk, rst : in  std_logic;
    valid    : in  std_logic;
    data     : in  std_logic_vector(7 downto 0);
    ready    : out std_logic;
    tx       : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  type state_t is (IDLE, START, BITS, STOP);
  signal state : state_t := IDLE;
  signal clk_cnt : natural range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx : natural range 0 to 7 := 0;
  signal shreg   : std_logic_vector(7 downto 0) := (others => '0');
begin
  ready <= '1' when state = IDLE else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE; tx <= '1'; clk_cnt <= 0; bit_idx <= 0;
      else
        case state is
          when IDLE =>
            tx <= '1';
            if valid = '1' then
              shreg <= data; clk_cnt <= 0; state <= START; tx <= '0';
            end if;
          when START =>
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0; bit_idx <= 0; state <= BITS; tx <= shreg(0);
            else
              clk_cnt <= clk_cnt + 1;
            end if;
          when BITS =>
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0;
              if bit_idx = 7 then
                state <= STOP; tx <= '1';
              else
                bit_idx <= bit_idx + 1;
                tx <= shreg(bit_idx + 1);
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;
          when STOP =>
            if clk_cnt = CLKS_PER_BIT - 1 then
              clk_cnt <= 0; state <= IDLE;
            else
              clk_cnt <= clk_cnt + 1;
            end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
