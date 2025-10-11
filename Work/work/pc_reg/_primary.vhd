library verilog;
use verilog.vl_types.all;
entity pc_reg is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        pc_src          : in     vl_logic;
        pc_next         : in     vl_logic_vector(31 downto 0);
        pc              : out    vl_logic_vector(31 downto 0)
    );
end pc_reg;
