library verilog;
use verilog.vl_types.all;
entity alu_core is
    port(
        op1             : in     vl_logic_vector(31 downto 0);
        op2             : in     vl_logic_vector(31 downto 0);
        alu_ctrl        : in     vl_logic_vector(3 downto 0);
        result          : out    vl_logic_vector(31 downto 0);
        zero            : out    vl_logic;
        slt             : out    vl_logic;
        sltu            : out    vl_logic
    );
end alu_core;
