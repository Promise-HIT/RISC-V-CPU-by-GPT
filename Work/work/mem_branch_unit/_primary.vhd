library verilog;
use verilog.vl_types.all;
entity mem_branch_unit is
    generic(
        IMEM_ADDR_WIDTH : integer := 10
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        pc              : in     vl_logic_vector(31 downto 0);
        imm             : in     vl_logic_vector(31 downto 0);
        branch          : in     vl_logic;
        branch_type     : in     vl_logic_vector(2 downto 0);
        zero            : in     vl_logic;
        slt             : in     vl_logic;
        sltu            : in     vl_logic;
        addr            : in     vl_logic_vector(31 downto 0);
        write_data      : in     vl_logic_vector(31 downto 0);
        mem_read        : in     vl_logic;
        mem_write       : in     vl_logic;
        mem_width       : in     vl_logic_vector(1 downto 0);
        mem_signed      : in     vl_logic;
        branch_target   : out    vl_logic_vector(31 downto 0);
        branch_taken    : out    vl_logic;
        read_data       : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IMEM_ADDR_WIDTH : constant is 1;
end mem_branch_unit;
