-- -----------------------------------------------------------------------------
--
--  Title      :  Edge-Detection design project - task 2.
--             :
--  Developers :  Jonas Fuhr Høyer - s253842@student.dtu.dk
--             :
--  Purpose    :  This design contains an entity for the accelerator that must be build
--             :  in task two of the Edge Detection design project.
--             :
--  Revision   :  1.0     Final version
--             :
--
-- -----------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- The entity for task two. Notice the additional signals for the memory.
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
  constant IMAGE_WIDTH        : integer               := 352;
  constant IMAGE_WIDTH_PADDED : integer               := 352 + 2;
  constant LINE_WIDTH         : integer               := 352 / 4;
  constant IMAGE_HEIGHT       : integer               := 288;
  constant MAX_ADDRESS        : unsigned(15 downto 0) := to_unsigned((IMAGE_WIDTH * IMAGE_HEIGHT) / 4 - 1, 16);

  type state_type is (IDLE, SETUP_LOAD_0, SETUP_LOAD_1, SETUP_READ_1, SETUP_LOAD_2, SETUP_READ_2, CALC, WRITE_ADDR, LOAD_LINE, READ_LINE, DONE);
  signal state          : state_type := IDLE;
  signal read_addr_reg  : halfword_t := (others => '0');
  signal write_addr_reg : halfword_t := std_logic_vector(MAX_ADDRESS + 1);
  type pixel_buffer_type is array(0 to 3) of std_logic_vector(7 downto 0);
  signal pixel_buffer : pixel_buffer_type;

  signal line_addr   : integer := 0;
  signal line_index  : integer := 1;
  signal pixel_count : integer := 0;
  type line_buffer_type is array(0 to IMAGE_WIDTH_PADDED - 1) of std_logic_vector(7 downto 0);
  signal line0                                       : line_buffer_type;
  signal line1                                       : line_buffer_type;
  signal line2                                       : line_buffer_type;
  signal s11, s12, s13, s21, s22, s23, s31, s32, s33 : std_logic_vector(7 downto 0);
begin
  process (clk, reset)
    variable dn, dx, dy : integer;
  begin
    if reset = '1' then
      state          <= IDLE;
      read_addr_reg  <= (others => '0');
      write_addr_reg <= std_logic_vector(MAX_ADDRESS + 1);
      line_addr      <= 0;
      line_index     <= 0;
    elsif rising_edge(clk) then
      state  <= state;
      addr   <= (others => 'Z');
      dataW  <= (others => 'Z');
      en     <= '0';
      we     <= '0';
      finish <= '0';
      case state is
        when IDLE =>
          if start = '1' then
            state <= SETUP_LOAD_0;
          end if;
        when SETUP_LOAD_0                        =>
          line0                         <= (others => (others => '0'));
          line1(0)                      <= (others => '0');
          line1(IMAGE_WIDTH_PADDED - 1) <= (others => '0');
          line2(0)                      <= (others => '0');
          line2(IMAGE_WIDTH_PADDED - 1) <= (others => '0');
          state                         <= SETUP_LOAD_1;
        when SETUP_LOAD_1 =>
          en    <= '1';
          state <= SETUP_READ_1;
          addr  <= read_addr_reg;
        when SETUP_READ_1 =>
          line1(line_index)     <= dataR(7 downto 0);
          line1(line_index + 1) <= dataR(15 downto 8);
          line1(line_index + 2) <= dataR(23 downto 16);
          line1(line_index + 3) <= dataR(31 downto 24);
          line_index            <= line_index + 4;
          line_addr             <= line_addr + 1;
          read_addr_reg         <= std_logic_vector(unsigned(read_addr_reg) + 1);
          if line_addr = LINE_WIDTH - 1 then
            line_index <= 1;
            line_addr  <= 0;
            state      <= SETUP_LOAD_2;
          else
            state <= SETUP_LOAD_1;
          end if;
        when SETUP_LOAD_2 =>
          en    <= '1';
          state <= SETUP_READ_2;
          addr  <= read_addr_reg;
        when SETUP_READ_2 =>
          line2(line_index)     <= dataR(7 downto 0);
          line2(line_index + 1) <= dataR(15 downto 8);
          line2(line_index + 2) <= dataR(23 downto 16);
          line2(line_index + 3) <= dataR(31 downto 24);
          line_index            <= line_index + 4;
          line_addr             <= line_addr + 1;
          read_addr_reg         <= std_logic_vector(unsigned(read_addr_reg) + 1);
          if line_addr = LINE_WIDTH - 1 then
            line_index <= 1;
            line_addr  <= 0;
            state      <= CALC;
          else
            state <= SETUP_LOAD_2;
          end if;
        when CALC =>
          s11 <= line0(line_index - 1);
          s12 <= line0(line_index);
          s13 <= line0(line_index + 1);
          s21 <= line1(line_index - 1);
          s22 <= line1(line_index);
          s23 <= line1(line_index + 1);
          s31 <= line2(line_index - 1);
          s32 <= line2(line_index);
          s33 <= line2(line_index + 1);
          dx := to_integer(signed('0' & s13) - signed('0' & s11) + 2 * (signed('0' & s23) - signed('0' & s21)) + signed('0' & s33) - signed('0' & s31));
          dy := to_integer(signed('0' & s11) - signed('0' & s31) + 2 * (signed('0' & s12) - signed('0' & s32)) + signed('0' & s13) - signed('0' & s33));
          if dx < 0 then
            dx := - dx;
          end if;
          if dy < 0 then
            dy := - dy;
          end if;
          dn := dx + dy;
          if dn > 255 then
            dn := 255;
          elsif dn < 0 then
            dn := 0;
          end if;
          pixel_buffer(pixel_count) <= std_logic_vector(to_unsigned(dn, 8));
          line_index                <= line_index + 1;
          pixel_count               <= pixel_count + 1;

          if pixel_count = 3 then
            pixel_count <= 0;
            state       <= WRITE_ADDR;
          else
            state <= CALC;
          end if;
        when WRITE_ADDR =>
          en             <= '1';
          we             <= '1';
          addr           <= write_addr_reg;
          write_addr_reg <= std_logic_vector(unsigned(write_addr_reg) + 1);
          dataW          <= pixel_buffer(3) & pixel_buffer(2) & pixel_buffer(1) & pixel_buffer(0);
          if line_index >= IMAGE_WIDTH then
            if read_addr_reg >= std_logic_vector(MAX_ADDRESS + 1) then
              state <= DONE;
            else
              line_index <= 1;
              line0      <= line1;
              line1      <= line2;
              state      <= LOAD_LINE;
            end if;
          else
            state <= CALC;
          end if;
        when LOAD_LINE =>
          en    <= '1';
          state <= READ_LINE;
          addr  <= read_addr_reg;
        when READ_LINE =>
          line2(line_index)     <= dataR(7 downto 0);
          line2(line_index + 1) <= dataR(15 downto 8);
          line2(line_index + 2) <= dataR(23 downto 16);
          line2(line_index + 3) <= dataR(31 downto 24);
          line_index            <= line_index + 4;
          line_addr             <= line_addr + 1;
          read_addr_reg         <= std_logic_vector(unsigned(read_addr_reg) + 1);
          if line_addr = LINE_WIDTH - 1 then
            line_index <= 1;
            line_addr  <= 0;
            state      <= CALC;
          else
            state <= LOAD_LINE;
          end if;
        when DONE =>
          finish <= '1';
      end case;
    end if;
  end process;
end rtl;
