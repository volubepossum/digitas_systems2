-- -----------------------------------------------------------------------------
--
--  Title      :  Edge-Detection design project - task 2.
--             :
--  Developers :  Jonas Fuhr Høyer - s253842@student.dtu.dk
--             :
--  Purpose    :  This design contains an entity for the accelerator inverting 
--             :  the inputted picture.
--             :
--  Revision   :  1.0    Final version
--             :
--
-- -----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The entity for task zero. Notice the additional signals for the memory.
-- reset is active high.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.types.all;

entity acc is
  port (
    clk    : in bit_t; -- The clock.
    reset  : in bit_t; -- The reset signal. Active high.
    addr   : out halfword_t; -- Address bus for data.
    dataR  : in word_t; -- The data bus.
    dataW  : out word_t; -- The data bus.
    en     : out bit_t; -- Request signal for data.
    we     : out bit_t; -- Read/Write signal for data.
    start  : in bit_t;
    finish : out bit_t
  );
end acc;

--------------------------------------------------------------------------------
-- The desription of the accelerator.
--------------------------------------------------------------------------------

architecture rtl of acc is
  type state_type is (IDLE, READ, WRITE, DONE);
  signal state, next_state       : state_type            := IDLE;
  constant MAX_ADDRESS           : unsigned(15 downto 0) := to_unsigned((352 * 288) / 4 - 1, 16);
  signal addr_reg, next_addr_reg : halfword_t            := (others => '0');
begin process (state, start, addr_reg, dataR) begin
  next_state       <= state;
  next_addr_reg    <= addr_reg;
  addr             <= (others => 'Z');
  dataW            <= (others => 'Z');
  en               <= '0';
  we               <= '0';
  finish           <= '0';
  case state is
    when IDLE =>
      if start = '1' then
        next_state <= READ;
      end if;
    when READ => en  <= '1';
      next_state       <= WRITE;
      addr             <= addr_reg;
    when WRITE => en <= '1';
      we               <= '1';
      dataW            <= not dataR;
      addr             <= std_logic_vector(unsigned(addr_reg) + MAX_ADDRESS + 1);
      if unsigned(addr_reg) = MAX_ADDRESS then
        next_state <= DONE;
      else
        next_addr_reg <= std_logic_vector(unsigned(addr_reg) + 1);
        next_state    <= READ;
      end if;
    when DONE => finish <= '1';
  end case;
end process;
process (clk, reset) begin if reset = '1' then
  state    <= IDLE;
  addr_reg <= (others => '0');
elsif rising_edge(clk) then
  state    <= next_state;
  addr_reg <= next_addr_reg;
end if;
end process;
end architecture rtl;