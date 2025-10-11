library verilog;
use verilog.vl_types.all;
entity dmem is
    generic(
        ADDR_WIDTH      : integer := 10
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        addr            : in     vl_logic_vector(31 downto 0);
        write_data      : in     vl_logic_vector(31 downto 0);
        mem_read_en     : in     vl_logic;
        mem_write_en    : in     vl_logic;
        mem_size        : in     vl_logic_vector(1 downto 0);
        mem_signed      : in     vl_logic;
        read_data       : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ADDR_WIDTH : constant is 1;
end dmem;
