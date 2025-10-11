library verilog;
use verilog.vl_types.all;
entity if_stage is
    generic(
        IMEM_ADDR_WIDTH : integer := 10
    );
    port(
        pc              : in     vl_logic_vector(31 downto 0);
        inst            : out    vl_logic_vector(31 downto 0);
        pc_plus_4       : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IMEM_ADDR_WIDTH : constant is 1;
end if_stage;
