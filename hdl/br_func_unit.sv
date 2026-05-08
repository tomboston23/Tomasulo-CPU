module br_func_unit
import cache_types::*;
(
    input  rs_entry_t  rs_entry,
    output cdb_t fu_result
);

    logic [31:0] a,b;
    logic [2:0] cmpop;
    logic cmpout;
    logic [2:0] funct3;

    cmp cmp_i (
        .a      (a),
        .b      (b),
        .cmpop  (cmpop),
        .cmpout (cmpout)
    );

    logic [6:0] opcode;
    assign opcode = rs_entry.inst.i_type.opcode;   
    assign funct3 = rs_entry.inst.r_type.funct3;

    logic [31:0] i_imm, j_imm, b_imm;
    assign i_imm = {{21{rs_entry.inst[31]}}, rs_entry.inst[30:20]};
    assign j_imm = {{12{rs_entry.inst[31]}}, rs_entry.inst[19:12], rs_entry.inst[20], rs_entry.inst[30:21], 1'b0};
    assign b_imm = {{20{rs_entry.inst[31]}}, rs_entry.inst[7], rs_entry.inst[30:25], rs_entry.inst[11:8], 1'b0};

    always_comb begin
        cmpop = '0;
        a = fu_result.rs1_v;
        b = fu_result.rs2_v;
        case(funct3)
            beq: cmpop = beq;
            bne: cmpop = bne;
            blt: cmpop = blt;
            bge: cmpop = bge;
            bltu: cmpop = bltu;
            bgeu: cmpop = bgeu;
            default: cmpop = '0;
        endcase
    end

    always_comb begin
        fu_result            = '0;
        fu_result.wb_tag   = rs_entry.dest_tag;
        fu_result.wb_physical_reg = rs_entry.dest_physical_reg; 
        fu_result.rs1_v = rs_entry.src1_value;
        fu_result.rs2_v = rs_entry.src2_value;
        fu_result.wb_valid      = 1'b0;
        fu_result.wb_value   = 32'b0;
        fu_result.inst = rs_entry.inst;
        //fu_result.order = rs_entry.order;

        if (rs_entry.valid) begin
            fu_result.wb_valid = 1'b1; 
            unique case (opcode)   
                op_jal: begin // j type
                    fu_result.pc_wdata = rs_entry.pc + j_imm;
                    fu_result.wb_value = rs_entry.pc + 'd4;
                end
                op_jalr: begin // i type
                    fu_result.pc_wdata = (fu_result.rs1_v + i_imm) & (~'d1);
                    fu_result.wb_value = rs_entry.pc + 'd4;
                end
                op_br: begin


                    fu_result.pc_wdata = cmpout ? rs_entry.pc + b_imm : rs_entry.pc + 'd4; 
                end
                default: fu_result = '0;
            endcase
        end
    end

endmodule : br_func_unit