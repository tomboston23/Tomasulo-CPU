module id_stage
import cache_types::*;
(

    input   if_id_reg_t     if_id_reg,
    output  id_dis_reg_t    id_dis_reg_next

);

logic call, ret;
logic [4:0] rs1_s, rs2_s, rd_s;

// assign id_dis_reg_next = '0;
always_comb begin
    id_dis_reg_next = '0;
    id_dis_reg_next.inst = if_id_reg.inst;
    id_dis_reg_next.pc = if_id_reg.pc;
    id_dis_reg_next.pc_next = if_id_reg.pc_next;
    id_dis_reg_next.tag = if_id_reg.tag;
    id_dis_reg_next.valid = if_id_reg.valid;
    rd_s = '0;
    rs1_s = '0;
    rs2_s = '0;
    call = '0;
    ret = '0;

    case(if_id_reg.inst.u_type.opcode) 
        op_lui: begin // u-type
            rd_s = if_id_reg.inst.u_type.rd;
        end
        op_auipc: begin //u-type
            rd_s = if_id_reg.inst.u_type.rd;
        end
        op_jal: begin // J-type
            rd_s = if_id_reg.inst.j_type.rd;
            if (rd_s == 5'b1) call = '1;
        end
        op_jalr: begin // I-type
            rs1_s = if_id_reg.inst.i_type.rs1;
            rd_s = if_id_reg.inst.i_type.rd;
        end
        op_br: begin // B-type
            rs1_s = if_id_reg.inst.r_type.rs1;
            rs2_s = if_id_reg.inst.r_type.rs2;
            rd_s  = '0;
        
        end
        op_load: begin // I-type
            rs1_s = if_id_reg.inst.i_type.rs1;
            rd_s = if_id_reg.inst.i_type.rd;
        end
        op_store: begin // S-type
            rs1_s = if_id_reg.inst.r_type.rs1;
            rs2_s = if_id_reg.inst.r_type.rs2;
        end
        op_imm: begin // I-type
            rs1_s = if_id_reg.inst.i_type.rs1;
            rd_s = if_id_reg.inst.i_type.rd;
        end
        op_reg: begin // R-type
            rs1_s = if_id_reg.inst.r_type.rs1;
            rs2_s = if_id_reg.inst.r_type.rs2;
            rd_s = if_id_reg.inst.r_type.rd;
        end
    endcase

    id_dis_reg_next.rs1_s = rs1_s;
    id_dis_reg_next.rs2_s = rs2_s;
    id_dis_reg_next.rd_s = rd_s;

end

endmodule : id_stage