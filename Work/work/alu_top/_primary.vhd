library verilog;
use verilog.vl_types.all;
entity alu_top is
    port(
        alu_op          : in     vl_logic_vector(2 downto 0);
        funct3          : in     vl_logic_vector(2 downto 0);
        funct7          : in     vl_logic_vector(6 downto 0);
        rs1_data        : in     vl_logic_vector(31 downto 0);
        rs2_data        : in     vl_logic_vector(31 downto 0);
        imm             : in     vl_logic_vector(31 downto 0);
        alu_src         : in     vl_logic;
        alu_result      : out    vl_logic_vector(31 downto 0);
        zero            : out    vl_logic;
        slt             : out    vl_logic;
        sltu            : out    vl_logic
    );
end alu_top;
