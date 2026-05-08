module mult_func_unit
import cache_types::*;
(
    input  logic       clk,
    input  logic       rst,
    input  rs_entry_t  rs_entry_mult,
    input  logic       can_begin,      // issue stage says FU can begin
    output cdb_t       fu_result_mult, // result to CDB
    output logic       mul_stall,      // stall to issue when busy
    output logic       op_done,
    input  logic       flush
);

    assign mul_stall = '0; // we don't ts 

    // local params that control multiplier and divider IPs
    localparam DATA_WIDTH   = 32;
    localparam A_WIDTH      = 33;
    localparam B_WIDTH      = 33;
    localparam TC_MODE      = 1;
    localparam RST_MODE     = 1;

    // DIFFERENT PIPELINE DEPTHS
    localparam MUL_STAGES        = 8;
    localparam DIV_STAGES        = 22;
    localparam MUL_RESULT_STAGE  = MUL_STAGES - 2;
    localparam DIV_RESULT_STAGE  = DIV_STAGES - 2;

    // Hold RS entry for decode / operand selection
    rs_entry_t rs_entry_hold; 
    always_comb begin
        if (can_begin && rs_entry_mult.valid)
            rs_entry_hold = rs_entry_mult;
        else
            rs_entry_hold = '0;
    end

    // Track if we flushed while an op was in-flight
    logic flush_latched; 
    always_ff @ (posedge clk) begin
        if (rst)
            flush_latched <= '0;
        else if (rs_entry_hold.valid & flush)
            flush_latched <= '1;
        else if (op_done | can_begin)
            flush_latched <= '0;
    end
    
    // Decode reservation station entry logic
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic       is_mul_op, is_div_op;

    assign funct3     = rs_entry_hold.inst.r_type.funct3;
    assign funct7     = rs_entry_hold.inst.r_type.funct7;
    assign is_mul_op  = (funct7 == 7'b0000001) && (funct3[2] == 1'b0);
    assign is_div_op  = (funct7 == 7'b0000001) && (funct3[2] == 1'b1);
    
    // Operands going into IPs
    logic [A_WIDTH-1:0] a_mul, b_mul, a_div, b_div, as, au, bs, bu;
    logic [A_WIDTH+B_WIDTH-1:0] product;
    logic [A_WIDTH-1:0]         quotient;
    logic [B_WIDTH-1:0]         remainder;
    logic                       divide_by_0;

    always_comb begin
        a_mul = '0;
        b_mul = '0;
        a_div = '0;
        b_div = '0;
        unique case (funct3) 
            mul, mulh: begin
                a_mul = as;
                b_mul = bs;
            end
            mulhsu: begin
                a_mul = as;
                b_mul = bu;
            end
            mulhu: begin
                a_mul = au;
                b_mul = bu;
            end
            div, rem: begin
                a_div = as;
                b_div = bs;
            end
            divu, remu: begin
                a_div = au;
                b_div = bu;
            end
            default: begin
                a_div = '0;
                b_div = '0;
                a_mul = '0;
                b_mul = '0;
            end
        endcase
    end

    assign as = {rs_entry_hold.src1_value[DATA_WIDTH-1], rs_entry_hold.src1_value};
    assign au = {1'b0, rs_entry_hold.src1_value};
    assign bs = {rs_entry_hold.src2_value[DATA_WIDTH-1], rs_entry_hold.src2_value};
    assign bu = {1'b0, rs_entry_hold.src2_value};

    // ============================================================
    //  SEPARATE META-DATA PIPELINES FOR MUL AND DIV
    // ============================================================
    rs_entry_t mul_meta  [MUL_STAGES];
    logic      mul_valid [MUL_STAGES];

    rs_entry_t div_meta  [DIV_STAGES];
    logic      div_valid [DIV_STAGES];

    always_ff @(posedge clk) begin
        if (rst || flush) begin 
            for (integer i = 0; i < MUL_STAGES; i++) begin
                mul_meta[i]  <= '0;
                mul_valid[i] <= 1'b0;
            end
            for (integer j = 0; j < DIV_STAGES; j++) begin
                div_meta[j]  <= '0;
                div_valid[j] <= 1'b0;
            end
        end else begin
            // shift MUL pipeline
            for (integer i = MUL_STAGES-1; i > 0; i--) begin
                mul_meta[i]  <= mul_meta[i-1];
                mul_valid[i] <= mul_valid[i-1];
            end
            // shift DIV pipeline
            for (integer j = DIV_STAGES-1; j > 0; j--) begin
                div_meta[j]  <= div_meta[j-1];
                div_valid[j] <= div_valid[j-1];
            end

            // stage 0 injection for MUL
            if (can_begin && rs_entry_mult.valid && is_mul_op) begin
                mul_meta[0]  <= rs_entry_mult;
                mul_valid[0] <= 1'b1;
            end else begin
                mul_meta[0]  <= '0;
                mul_valid[0] <= 1'b0;
            end

            // stage 0 injection for DIV
            if (can_begin && rs_entry_mult.valid && is_div_op) begin
                div_meta[0]  <= rs_entry_mult;
                div_valid[0] <= 1'b1;
            end else begin
                div_meta[0]  <= '0;
                div_valid[0] <= 1'b0;
            end
        end
    end

    // ============================================================
    //  INPUTS TO THE MULTIPLIER/DIVIDER IPs
    // ============================================================
    logic [A_WIDTH-1:0] mul_in_A, div_in_A;
    logic [B_WIDTH-1:0] mul_in_B, div_in_B;

    assign mul_in_A = is_mul_op ? a_mul : '0;
    assign mul_in_B = is_mul_op ? b_mul : '0;
    assign div_in_A = is_div_op ? a_div : '0;
    assign div_in_B = is_div_op ? b_div : '0;

    // Multiplier with MUL_STAGES
    DW_mult_pipe #(
        .a_width    (A_WIDTH),
        .b_width    (B_WIDTH),
        .num_stages (MUL_STAGES),
        .stall_mode (0),
        .rst_mode   (RST_MODE),
        .op_iso_mode(0)
    ) mult_pipe_core (
        .clk    (clk),
        .rst_n  (~(rst | flush)),
        .en     (1'b1),
        .tc     ('1),
        .a      (mul_in_A),
        .b      (mul_in_B),
        .product(product)
    );

    // Divider with DIV_STAGES
    DW_div_pipe #(
        .a_width    (A_WIDTH),
        .b_width    (B_WIDTH),
        .tc_mode    (TC_MODE),
        .rem_mode   (1),
        .num_stages (DIV_STAGES),
        .stall_mode (0),
        .rst_mode   (RST_MODE),
        .op_iso_mode(0)
    ) div_pipe_core (
        .clk        (clk),
        .rst_n      (~(rst | flush)),
        .en         (1'b1),
        .a          (div_in_A),
        .b          (div_in_B),
        .quotient   (quotient),
        .remainder  (remainder),
        .divide_by_0(divide_by_0)
    );

    // ============================================================
    //  PICK RESULT FROM MUL OR DIV PIPELINE
    // ============================================================
    rs_entry_t mul_last_entry, div_last_entry;
    logic      mul_last_valid, div_last_valid;

    assign mul_last_entry = mul_meta[MUL_RESULT_STAGE];
    assign mul_last_valid = mul_valid[MUL_RESULT_STAGE];

    assign div_last_entry = div_meta[DIV_RESULT_STAGE];
    assign div_last_valid = div_valid[DIV_RESULT_STAGE];

    // Simple priority: MUL result wins if both ready same cycle
    rs_entry_t last_entry;
    logic      last_valid;
    logic      use_mul_result, use_div_result;

    always_comb begin
        use_mul_result = mul_last_valid;
        use_div_result = (~mul_last_valid) & div_last_valid;

        last_entry = '0;
        last_valid = 1'b0;

        if (use_mul_result) begin
            last_entry = mul_last_entry;
            last_valid = 1'b1;
        end else if (use_div_result) begin
            last_entry = div_last_entry;
            last_valid = 1'b1;
        end
    end

    // select correct 32-b*t result based on funct3 of last_entry
    logic [31:0] outcome;
    always_comb begin
        outcome = '0;
        if (last_valid) begin
            unique case (last_entry.inst.r_type.funct3)
                // multiplication results
                3'b000:               outcome = product[31:0];      // MUL
                3'b001, 3'b010, 3'b011: outcome = product[63:32];   // MULH, MULHSU, MULHU

                // division results
                3'b100, 3'b101: begin // DIV, DIVU
                    if (divide_by_0) outcome = 32'hFFFF_FFFF;
                    else            outcome = quotient[31:0];
                end

                // remainder results
                3'b110, 3'b111: begin // REM, REMU
                    if (divide_by_0) outcome = last_entry.src1_value;
                    else            outcome = remainder[31:0];
                end

                default: outcome = '0;
            endcase
        end
    end

    // goes high when either pipeline has a valid result
    assign op_done = last_valid;

    // ============================================================
    //  CDB Logic
    // ============================================================
    cdb_t fu_res_next;
    always_comb begin
        fu_res_next = '0;
        if (last_valid) begin
            fu_res_next.wb_value        = outcome;
            fu_res_next.wb_tag          = last_entry.dest_tag;
            fu_res_next.wb_physical_reg = last_entry.dest_physical_reg;
            fu_res_next.rs1_v           = last_entry.src1_value;
            fu_res_next.rs2_v           = last_entry.src2_value;
            fu_res_next.wb_valid        = 1'b1;
            fu_res_next.inst            = last_entry.inst;
            // fu_res_next.order        = last_entry.order;
        end
    end

    // send output to CDB 
    always_ff @(posedge clk) begin
        if (rst)
            fu_result_mult <= '0;
        else
            fu_result_mult <= flush_latched ? '0 : fu_res_next;
    end

endmodule : mult_func_unit
