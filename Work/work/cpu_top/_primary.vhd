library verilog;
use verilog.vl_types.all;
entity cpu_top is
    generic(
        IMEM_ADDR_WIDTH : integer := 10;
        DMEM_ADDR_WIDTH : integer := 10
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        dbg_pc          : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IMEM_ADDR_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of DMEM_ADDR_WIDTH : constant is 1;
end cpu_top;
