library verilog;
use verilog.vl_types.all;
entity wb_controller is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        dec_reg_write   : in     vl_logic;
        dec_wb_sel      : in     vl_logic_vector(1 downto 0);
        dec_rd          : in     vl_logic_vector(4 downto 0);
        dec_imm_u       : in     vl_logic_vector(31 downto 0);
        alu_result      : in     vl_logic_vector(31 downto 0);
        mem_read_data   : in     vl_logic_vector(31 downto 0);
        pc_plus_4       : in     vl_logic_vector(31 downto 0);
        rf_we           : out    vl_logic;
        rf_wd_idx       : out    vl_logic_vector(4 downto 0);
        rf_wd_data      : out    vl_logic_vector(31 downto 0)
    );
end wb_controller;
