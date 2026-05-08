module issue
import cache_types::*;
(
    // input  logic       clk,
    // input  logic       rst,
    // coming from reservation station 
    input  rs_entry_t  alu_inst,
    input  rs_entry_t  muldi_inst,
    input  rs_entry_t  mem_inst,
    input  rs_entry_t  br_inst,
    
    // functional unit signals that its done 
    input  logic       mult_ready,
    input  logic       alu_ready,
    input  logic       memory_ready,
    input  logic       branch_ready,
    
    //  issue valid signals 
    output logic       can_begin_alu,
    output logic       can_begin_mult,
    output logic       can_begin_mem,
    output logic       can_begin_br
);
    logic lint; 
    assign lint = memory_ready &&  branch_ready ; // for lint
 

    always_comb begin
        can_begin_alu = 1'b0;
        can_begin_mult = 1'b0;
        can_begin_mem = 1'b0;
        can_begin_br = 1'b0;
        
        if ( alu_ready && alu_inst.valid ) begin
            //  op_imm: only need src1 ready
            //  op_reg: need both src1 and src2 ready
            // op_lui: dont need 
            case (alu_inst.inst.i_type.opcode)
                op_imm: begin
                    if (alu_inst.src1_ready) begin
                        can_begin_alu = 1'b1;
                    end
                end
                op_reg: begin
                    if (alu_inst.src1_ready && alu_inst.src2_ready) begin
                        can_begin_alu = 1'b1;
                    end
                end
                op_lui: begin
                    can_begin_alu = 1'b1;
                end
                default: begin
                    can_begin_alu = 1'b0;
                end
            endcase
        end
        
        if (mult_ready && muldi_inst.valid) begin
            // muldi will alwys need both operands 
            if (muldi_inst.src1_ready && muldi_inst.src2_ready) begin
                can_begin_mult= 1'b1;
            end
        end


        if (memory_ready && mem_inst.valid) begin
            // load: need src1 (address) ready
            // store: need src1 (address) and src2 (data) ready
            case (mem_inst.inst.i_type.opcode)
                op_load: begin
                    if (mem_inst.src1_ready) begin
                        can_begin_mem = 1'b1;
                    end
                end
                op_store: begin
                    if (mem_inst.src1_ready && mem_inst.src2_ready) begin
                        can_begin_mem = 1'b1;
                    end
                end
                default: begin
                    can_begin_mem = 1'b0;
                end
            endcase
        end

        
        if (branch_ready && br_inst.valid) begin
            if (br_inst.src1_ready && br_inst.src2_ready) begin
                can_begin_br = '1;
            end
        end
        
    end


endmodule: issue