library verilog;
use verilog.vl_types.all;
entity regfile is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        reg_write       : in     vl_logic;
        rs1_idx         : in     vl_logic_vector(4 downto 0);
        rs2_idx         : in     vl_logic_vector(4 downto 0);
        rd_idx          : in     vl_logic_vector(4 downto 0);
        rd_wdata        : in     vl_logic_vector(31 downto 0);
        rs1_data        : out    vl_logic_vector(31 downto 0);
        rs2_data        : out    vl_logic_vector(31 downto 0)
    );
end regfile;
