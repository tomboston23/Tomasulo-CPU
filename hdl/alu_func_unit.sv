module alu_func_unit
import cache_types::*;
(
    input  rs_entry_t  rs_entry,
    output cdb_t fu_result
);

    logic [31:0]                      a, b;
    logic signed   [31:0]             as, bs;
    logic unsigned [31:0]             au, bu;
    rv32i_opcode                      opcode;
    logic [2:0]                       f3;
    logic [6:0]                       f7;

    logic [31:0]                      i_imm_sext;  // sign-extended I-imm
    logic [31:0]                      u_imm_lui;   

    alu_ops                           aluop;
    logic [31:0]                      aluout;

    // extract fields from struct 

    assign opcode = rs_entry.inst.i_type.opcode;        
    assign f3 = (opcode == op_reg) ? rs_entry.inst.r_type.funct3 : rs_entry.inst.i_type.funct3;

    // rtype only
    assign f7  = (opcode == op_reg) ? rs_entry.inst.r_type.funct7 : 7'b0;

    // itype sext
    assign i_imm_sext = {{21{rs_entry.inst.word[31]}}, rs_entry.inst.word[30:20]};
    assign u_imm_lui  = {rs_entry.inst.word[31:12], 12'h000};
    // fixed imm's - Tom
    // just get immediates from mp verif, don't trust the instr_t struct

    assign as = signed'(a);
    assign bs = signed'(b);
    assign au = unsigned'(a);
    assign bu = unsigned'(b);

    alu alu_inst (
        .aluop (aluop),
        .a     (a),
        .b     (b),
        .aluout(aluout)
    );

    always_comb begin
        fu_result            = '0;
        fu_result.wb_tag   = rs_entry.dest_tag;
        fu_result.wb_physical_reg = rs_entry.dest_physical_reg; 
        fu_result.rs1_v = rs_entry.src1_value;
        fu_result.rs2_v = rs_entry.src2_value;
        fu_result.wb_valid      = 1'b0;
        fu_result.wb_value   = 32'b0;
        fu_result.inst = rs_entry.inst;
        a      = 32'b0;
        b      = 32'b0;
        aluop  = alu_add;  
        //fu_result.order = rs_entry.order;      

        //op_imm needs src1 only; op_reg needs both; LUI needs neither.
        if (rs_entry.valid) begin
            fu_result.wb_valid = 1'b1; 
            unique case (opcode)
                op_imm: begin
                    if (rs_entry.src1_ready) begin
                        a = rs_entry.src1_value;
                        b = i_imm_sext;
                        
                        unique case (arith_funct3_t'(f3))
                            add: begin
                                aluop = alu_add;
                                fu_result.wb_value = aluout;
                            end
                            sll: begin
                                aluop = alu_sll;
                                fu_result.wb_value = aluout;
                            end
                            slt: begin
                                fu_result.wb_value = {{31{1'b0}}, (as < signed'(b))};
                            end
                            sltu: begin
                                fu_result.wb_value = {{31{1'b0}}, (au < unsigned'(b))};
                            end
                            axor: begin
                                aluop = alu_xor;
                                fu_result.wb_value = aluout;
                            end
                            sr: begin
                                if (rs_entry.inst.i_type.i_imm[11:5] == 7'b0100000)
                                    aluop = alu_sra;
                                else
                                    aluop = alu_srl;
                                fu_result.wb_value = aluout;
                            end
                            aor: begin
                                aluop = alu_or;
                                fu_result.wb_value = aluout;
                            end
                            aand: begin
                                aluop = alu_and;
                                fu_result.wb_value = aluout;
                            end
                            default: begin
                                aluop = alu_add;
                                fu_result.wb_value = aluout;
                            end
                        endcase
                    end
                end

                op_reg: begin
                    if (rs_entry.src1_ready && rs_entry.src2_ready) begin
                        a = rs_entry.src1_value;
                        b = rs_entry.src2_value;

                        unique case (arith_funct3_t'(f3))
                            add: begin
                                aluop = (f7[5]) ? alu_sub : alu_add;
                                fu_result.wb_value = aluout;
                            end
                            sll: begin
                                aluop = alu_sll;
                                fu_result.wb_value = aluout;
                            end
                            slt: begin
                                fu_result.wb_value = {{31{1'b0}}, (as < bs)};
                            end
                            sltu: begin
                                fu_result.wb_value = {{31{1'b0}}, (au < bu)};
                            end
                            axor: begin
                                aluop = alu_xor;
                                fu_result.wb_value = aluout;
                            end
                            sr: begin
                                aluop = (f7[5]) ? alu_sra : alu_srl;
                                fu_result.wb_value = aluout;
                            end
                            aor: begin
                                aluop = alu_or;
                                fu_result.wb_value = aluout;
                            end
                            aand: begin
                                aluop = alu_and;
                                fu_result.wb_value = aluout;
                            end
                            default: begin
                                aluop = alu_add;
                                fu_result.wb_value = aluout;
                            end
                        endcase
                    end
                end

                // need to add auipc here somehow ? 
                op_lui: begin
                    fu_result.wb_value = u_imm_lui; 
                end

                op_auipc: begin
                    fu_result.wb_value = rs_entry.pc + u_imm_lui;
                end
                
                default: begin
                    //valid=0, busy=0
                end
            endcase
        end
    end

endmodule: alu_func_unit