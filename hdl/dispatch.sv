module dispatch
import cache_types::*; (
    //struct that decode stage passes in to dispatch
    input id_dis_reg_t decode_in,
    input logic global_stall,
    
    //signal going into rob  
    output rob_entry_t rob_out,
    //signals going into the four reservation stations
    output rs_entry_t mul_rs_out,
    output rs_entry_t alu_rs_out,
    output rs_entry_t mem_rs_out,
    output rs_entry_t branch_rs_out,
    //ROB inputs
    input logic alu_rs_full, mul_rs_full, mem_rs_full, br_rs_full,
    output logic dispatch_stall,
    input logic [PRF_BITS:0] rs1_paddr, rs2_paddr,
    output logic [PRF_BITS:0] rd_paddr,
    input logic rs1_ready, rs2_ready,
    input logic [31:0] rs1_v, rs2_v,


    output logic                    lsq_alloc_valid,
    output logic                    lsq_alloc_is_load,
    output logic                    lsq_alloc_is_store,
    output logic [ROB_BITS-1:0]     lsq_alloc_rob_tag,
    // output logic [63:0]             lsq_alloc_order,
    output logic [31:0]             lsq_alloc_inst,
    output logic [PRF_BITS:0]       lsq_alloc_dest_preg,
    
    // NEW: LSQ full signals (directly from LSQ, not through RS)
    input  logic                    lsq_ld_full,
    input  logic                    lsq_st_full
); 

    // Detect memory operations
    logic is_mem_op, is_load_op, is_store_op;
    assign is_load_op  = (decode_in.inst.r_type.opcode == op_load);
    assign is_store_op = (decode_in.inst.r_type.opcode == op_store);
    assign is_mem_op   = is_load_op || is_store_op;


    always_comb begin
        lsq_alloc_valid     = decode_in.valid && !global_stall && is_mem_op; // we only alloc stores on dispatch. loads don't need to be in-order
        lsq_alloc_is_load   = is_load_op;
        lsq_alloc_is_store  = is_store_op;
        lsq_alloc_rob_tag   = decode_in.tag;
        // lsq_alloc_order     = decode_in.order;
        lsq_alloc_inst      = decode_in.inst.word;
        lsq_alloc_dest_preg = rd_paddr;
    end

    rob_entry_t curr_rob;
    always_comb begin
        curr_rob = '0;
        curr_rob.valid = decode_in.valid && !global_stall;
        curr_rob.instruction = decode_in.inst;
        curr_rob.rd_s = decode_in.rd_s;
        curr_rob.is_store = is_store_op;
        curr_rob.is_load = is_load_op;
        //rvfi signals
        curr_rob.pc = decode_in.pc;
        curr_rob.pc_next = decode_in.pc_next;
        curr_rob.pc_pred = decode_in.pc_next;
        curr_rob.rs1_s = decode_in.rs1_s;
        curr_rob.rs2_s = decode_in.rs2_s;
        curr_rob.rs1_v = rs1_v;
        curr_rob.rs2_v = rs2_v;
        // curr_rob.order = decode_in.order;
        curr_rob.dest_physical_reg = rd_paddr;
        curr_rob.tag = decode_in.tag;
    end
    assign rob_out = curr_rob;
    assign rd_paddr = (|decode_in.rd_s) ? {1'b1, decode_in.tag} : '0;


    rs_entry_t curr_rs;
    always_comb begin
        curr_rs.valid = decode_in.valid && !global_stall;
        curr_rs.inst = decode_in.inst;
        curr_rs.src1_ready = rs1_ready;
        curr_rs.src1_value = rs1_v;
        curr_rs.src1_physical_reg = rs1_paddr;
        
        curr_rs.src2_ready = rs2_ready;
        curr_rs.src2_value = rs2_v;
        curr_rs.src2_physical_reg = rs2_paddr;
        curr_rs.dest_tag = decode_in.tag;
        curr_rs.is_store = is_store_op;
        curr_rs.is_load = is_load_op;
        curr_rs.dest_physical_reg = rd_paddr;
        //curr_rs.order = decode_in.order;
        curr_rs.pc = decode_in.pc;
    end


    always_comb begin
        mul_rs_out = '0;
        alu_rs_out = '0;
        mem_rs_out = '0;
        branch_rs_out = '0;
        dispatch_stall = '0;

        unique case (decode_in.inst.r_type.opcode)
            op_imm, op_auipc, op_lui: begin
                alu_rs_out = curr_rs;
                dispatch_stall = alu_rs_full;
            end
            op_reg: begin
                if(decode_in.inst.r_type.funct7[0]) begin
                    mul_rs_out = curr_rs;
                    dispatch_stall = mul_rs_full;
                end
                else begin 
                    alu_rs_out = curr_rs;
                    dispatch_stall = alu_rs_full;
                end
            end
            op_load: begin
                mem_rs_out = curr_rs;
                // Stall if EITHER RS is full OR LSQ load queue is full
                dispatch_stall = mem_rs_full || lsq_ld_full;
            end
            op_store: begin
                mem_rs_out = curr_rs;
                // Stall if EITHER RS is full OR LSQ store queue is full
                dispatch_stall = mem_rs_full || lsq_st_full;
            end
            op_br, op_jal, op_jalr: begin 
                branch_rs_out = curr_rs;
                dispatch_stall = br_rs_full;
            end
            default: begin
                dispatch_stall = '0;
            end
        endcase
    end 

endmodule