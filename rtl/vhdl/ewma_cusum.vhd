-- ewma_cusum.vhd : drift detector for one sensor channel (VHDL-2008)
--
--  * calibration : mean of the first 2**CALIB_LOG2 samples becomes the baseline
--  * EWMA        : y <- y + (x - y) / 2**EWMA_K            (smoothed value)
--  * two-sided CUSUM on (x - baseline) with allowance CUSUM_K, threshold CUSUM_H
--
-- All arithmetic is fixed point (FRAC fractional bits) so a Python model can
-- reproduce every output bit exactly (model/edge_model.py).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ewma_cusum is
  generic (
    DATA_W     : positive := 12;
    FRAC       : positive := 4;
    CALIB_LOG2 : positive := 7;    -- baseline window = 128 samples
    EWMA_K     : positive := 3;    -- alpha = 1/8
    CUSUM_K    : natural  := 96;   -- allowance, 16 units = 1 ADC count
    CUSUM_H    : natural  := 720   -- decision threshold
  );
  port (
    clk, rst     : in  std_logic;
    s_valid      : in  std_logic;                              -- one pulse per new sample
    s_data       : in  std_logic_vector(DATA_W - 1 downto 0);
    o_valid      : out std_logic;                              -- one pulse per processed sample
    o_ewma       : out std_logic_vector(DATA_W - 1 downto 0);
    o_alarm_pos  : out std_logic;                              -- upward drift
    o_alarm_neg  : out std_logic                               -- downward drift
  );
end entity;

architecture rtl of ewma_cusum is
  constant SW    : positive := DATA_W + FRAC + 4;              -- signed working width
  constant CLAMP : natural  := 4 * CUSUM_H;
  constant MAXV  : signed(SW - 1 downto 0) := to_signed(2 ** DATA_W - 1, SW);

  type state_t is (CALIB, RUN);
  signal state    : state_t := CALIB;
  signal cnt      : unsigned(CALIB_LOG2 downto 0) := (others => '0');
  signal acc      : unsigned(DATA_W + CALIB_LOG2 - 1 downto 0) := (others => '0');
  signal baseline : signed(SW - 1 downto 0) := (others => '0');
  signal ewma     : signed(SW - 1 downto 0) := (others => '0');
  signal sp, sn   : signed(SW - 1 downto 0) := (others => '0');
begin
  process (clk)
    variable x_fx, ew_n, e, sp_n, sn_n, y : signed(SW - 1 downto 0);
    variable acc_n : unsigned(acc'range);
    variable x_u   : unsigned(DATA_W - 1 downto 0);
    variable base_u : unsigned(DATA_W + CALIB_LOG2 + FRAC - 1 downto 0);   -- no overflow in acc << FRAC
  begin
    if rising_edge(clk) then
      o_valid <= '0';
      if rst = '1' then
        state <= CALIB;
        cnt   <= (others => '0');
        acc   <= (others => '0');
        baseline <= (others => '0');
        ewma  <= (others => '0');
        sp    <= (others => '0');
        sn    <= (others => '0');
        o_ewma <= (others => '0');
        o_alarm_pos <= '0';
        o_alarm_neg <= '0';
      elsif s_valid = '1' then
        x_u  := unsigned(s_data);
        x_fx := shift_left(signed(resize(x_u, SW)), FRAC);
        case state is
          when CALIB =>
            acc_n := acc + resize(x_u, acc'length);
            acc   <= acc_n;
            o_ewma <= s_data;                                  -- pass-through while calibrating
            o_alarm_pos <= '0';
            o_alarm_neg <= '0';
            if cnt = to_unsigned(2 ** CALIB_LOG2 - 1, cnt'length) then
              base_u   := shift_right(shift_left(resize(acc_n, base_u'length), FRAC), CALIB_LOG2);
              baseline <= signed(resize(base_u, SW));
              ewma     <= signed(resize(base_u, SW));
              state    <= RUN;
            end if;
            cnt <= cnt + 1;
          when RUN =>
            ew_n := ewma + shift_right(x_fx - ewma, EWMA_K);   -- arithmetic shift (floor)
            e    := x_fx - baseline;
            sp_n := sp + e - to_signed(CUSUM_K, SW);
            sn_n := sn - e - to_signed(CUSUM_K, SW);
            if sp_n < 0 then sp_n := (others => '0'); end if;
            if sn_n < 0 then sn_n := (others => '0'); end if;
            if sp_n > to_signed(CLAMP, SW) then sp_n := to_signed(CLAMP, SW); end if;
            if sn_n > to_signed(CLAMP, SW) then sn_n := to_signed(CLAMP, SW); end if;
            ewma <= ew_n;
            sp   <= sp_n;
            sn   <= sn_n;
            y := shift_right(ew_n + to_signed(2 ** (FRAC - 1), SW), FRAC);
            if y < 0 then y := (others => '0'); end if;
            if y > MAXV then y := MAXV; end if;
            o_ewma <= std_logic_vector(y(DATA_W - 1 downto 0));
            if sp_n > to_signed(CUSUM_H, SW) then o_alarm_pos <= '1'; else o_alarm_pos <= '0'; end if;
            if sn_n > to_signed(CUSUM_H, SW) then o_alarm_neg <= '1'; else o_alarm_neg <= '0'; end if;
        end case;
        o_valid <= '1';
      end if;
    end if;
  end process;
end architecture;
