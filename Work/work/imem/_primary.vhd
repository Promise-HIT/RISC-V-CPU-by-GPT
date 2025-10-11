library verilog;
use verilog.vl_types.all;
entity imem is
    generic(
        ADDR_WIDTH      : integer := 10
    );
    port(
        addr            : in     vl_logic_vector(31 downto 0);
        inst            : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ADDR_WIDTH : constant is 1;
end imem;
