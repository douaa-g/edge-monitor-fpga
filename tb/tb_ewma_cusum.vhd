-- Self-checking testbench: RTL vs. golden vectors from model/edge_model.py
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_ewma_cusum is
  generic (VEC_FILE : string := "results/vec_core.txt");
end entity;

architecture sim of tb_ewma_cusum is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal s_valid, o_valid, ap, an : std_logic := '0';
  signal s_data, o_ewma : std_logic_vector(11 downto 0) := (others => '0');
begin
  clk <= not clk after 5 ns;

  dut : entity work.ewma_cusum
    port map (clk => clk, rst => rst, s_valid => s_valid, s_data => s_data,
              o_valid => o_valid, o_ewma => o_ewma, o_alarm_pos => ap, o_alarm_neg => an);

  stim : process
    file f : text open read_mode is VEC_FILE;
    variable l : line;
    variable x, y, p, n : integer;
    variable total, errors : natural := 0;
  begin
    wait for 50 ns; rst <= '0'; wait until rising_edge(clk);
    while not endfile(f) loop
      readline(f, l);
      read(l, x); read(l, y); read(l, p); read(l, n);
      s_data  <= std_logic_vector(to_unsigned(x, 12));
      s_valid <= '1';
      wait until rising_edge(clk);
      s_valid <= '0';
      wait until rising_edge(clk) and o_valid = '1';
      total := total + 1;
      if to_integer(unsigned(o_ewma)) /= y or ap /= to_unsigned(p, 1)(0) or an /= to_unsigned(n, 1)(0) then
        errors := errors + 1;
        if errors <= 5 then
          report "MISMATCH sample " & integer'image(total - 1) & " got ewma=" &
                 integer'image(to_integer(unsigned(o_ewma))) & " exp=" & integer'image(y) severity warning;
        end if;
      end if;
      wait until rising_edge(clk);
    end loop;
    report "ewma_cusum: " & integer'image(total) & " vectors, " & integer'image(errors) & " mismatches";
    assert errors = 0 report "TEST FAILED" severity failure;
    report "TEST PASSED";
    finish;
  end process;
end architecture;
