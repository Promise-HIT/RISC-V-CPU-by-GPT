library verilog;
use verilog.vl_types.all;
entity decoder is
    port(
        inst            : in     vl_logic_vector(31 downto 0);
        opcode          : out    vl_logic_vector(6 downto 0);
        funct3          : out    vl_logic_vector(2 downto 0);
        funct7          : out    vl_logic_vector(6 downto 0);
        raw_rd          : out    vl_logic_vector(4 downto 0);
        raw_rs1         : out    vl_logic_vector(4 downto 0);
        raw_rs2         : out    vl_logic_vector(4 downto 0);
        rd_eff          : out    vl_logic_vector(4 downto 0);
        rs1_eff         : out    vl_logic_vector(4 downto 0);
        rs2_eff         : out    vl_logic_vector(4 downto 0);
        rd_v            : out    vl_logic;
        rs1_v           : out    vl_logic;
        rs2_v           : out    vl_logic;
        imm             : out    vl_logic_vector(31 downto 0);
        reg_write       : out    vl_logic;
        wb_sel          : out    vl_logic_vector(1 downto 0);
        alu_src         : out    vl_logic;
        alu_op          : out    vl_logic_vector(2 downto 0);
        mem_read        : out    vl_logic;
        mem_write       : out    vl_logic;
        mem_width       : out    vl_logic_vector(1 downto 0);
        mem_signed      : out    vl_logic;
        branch          : out    vl_logic;
        branch_type     : out    vl_logic_vector(2 downto 0);
        jump            : out    vl_logic;
        jalr            : out    vl_logic;
        lui             : out    vl_logic;
        auipc           : out    vl_logic;
        illegal         : out    vl_logic
    );
end decoder;
