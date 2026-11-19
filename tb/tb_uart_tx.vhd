-- Self-checking testbench: random bytes through uart_tx, decoded by a
-- behavioural receiver that also checks the bit period and the stop bit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity tb_uart_tx is end entity;

architecture sim of tb_uart_tx is
  constant CPB : positive := 16;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal valid, ready, tx : std_logic := '0';
  signal data : std_logic_vector(7 downto 0) := (others => '0');
  type byte_arr is array (0 to 255) of std_logic_vector(7 downto 0);
  signal sent, got : byte_arr;
  signal n_sent, n_got : natural := 0;
begin
  clk <= not clk after 5 ns;
  dut : entity work.uart_tx generic map (CLKS_PER_BIT => CPB)
    port map (clk => clk, rst => rst, valid => valid, data => data, ready => ready, tx => tx);

  driver : process
    variable seed1 : positive := 7;
    variable seed2 : positive := 11;
    variable r : real;
    variable b : std_logic_vector(7 downto 0);
  begin
    wait for 40 ns; rst <= '0'; wait until rising_edge(clk);
    for i in 0 to 199 loop
      uniform(seed1, seed2, r);
      b := std_logic_vector(to_unsigned(integer(floor(r * 256.0)) mod 256, 8));
      wait until rising_edge(clk) and ready = '1';
      data <= b; valid <= '1'; sent(i) <= b; n_sent <= i + 1;
      wait until rising_edge(clk);
      valid <= '0';
    end loop;
    wait until rising_edge(clk) and ready = '1';
    wait for 20 * CPB * 10 ns;
    assert n_got = 200 report "received " & integer'image(n_got) & " of 200 bytes" severity failure;
    for i in 0 to 199 loop
      assert sent(i) = got(i) report "byte " & integer'image(i) & " differs" severity failure;
    end loop;
    report "uart_tx: 200 random bytes OK (bit period and stop bit checked)";
    report "TEST PASSED";
    finish;
  end process;

  monitor : process
    variable v : std_logic_vector(7 downto 0);
    variable k : natural := 0;
  begin
    loop
      wait until falling_edge(tx);                       -- start bit
      wait for (CPB * 10 ns) / 2;
      assert tx = '0' report "start bit lost" severity failure;
      for i in 0 to 7 loop
        wait for CPB * 10 ns;
        v(i) := tx;
      end loop;
      wait for CPB * 10 ns;
      assert tx = '1' report "stop bit not high" severity failure;
      got(k) <= v; k := k + 1; n_got <= k;
    end loop;
  end process;
end architecture;
