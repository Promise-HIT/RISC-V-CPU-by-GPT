library verilog;
use verilog.vl_types.all;
entity tb_cpu_top is
    generic(
        IMEM_ADDR_WIDTH : integer := 6;
        DMEM_ADDR_WIDTH : integer := 6
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of IMEM_ADDR_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of DMEM_ADDR_WIDTH : constant is 1;
end tb_cpu_top;
