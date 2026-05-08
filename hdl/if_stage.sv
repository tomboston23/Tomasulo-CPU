module if_stage
import cache_types::*;
(
    input   logic           clk,
    input   logic           rst,
  
    input   logic           flush,
    input   logic           global_stall, 
    
    output  logic   [31:0]  fetch_addr,
    output  logic   [3:0]   fetch_rmask,
    input   logic   [31:0]  fetch_rdata,

    //line buffer
    input logic [255:0] dfp_rdata_buf,
    input logic [31:0]  dfp_addr_buf,
    output logic        imem_valid,

    //NLP
    input logic          pf_valid,
    input logic [31:0]   pf_addr_buf,
    input logic [255:0]  pf_rdata_buf,
    
    output  if_id_reg_t  if_id_reg_out,
    input  logic [ROB_BITS-1:0]  flush_tag,
    input  logic [31:0]  flush_pc,
    output logic         fetch,

    //training info from commit
    input   logic        br_commit_valid,
    input   logic [31:0] br_commit_pc,
    input   logic [31:0] br_commit_pc_next,

    input   logic                jalr_valid,
    input   logic [ROB_BITS-1:0] jalr_wb_tag,
    input   logic [31:0]         jalr_target, 
    input   logic                jalr_commit_valid,
    input   logic [31:0]         jalr_commit_rd_v,
    input   instr_t              jalr_commit_inst
    // input   logic [GHT_BITS-1:0]  br_commit_ghr
);
    //local params for branch predictor
    localparam SAT_CNTR_BITS = 2;


    localparam RAS_ENTRIES = 16; // RAS entries
    localparam ADDR_BITS = (RAS_ENTRIES <= 1) ? 1 : $clog2(RAS_ENTRIES); // b*ts for RAS head/tail ptr

    logic buffered, prev_buffered, pf_buffered, prev_pfb;
    assign fetch = (~buffered & prev_buffered) | (~pf_buffered & prev_pfb);

    always_comb begin
        if (fetch) fetch_rmask = '1;
        else       fetch_rmask = '0;
    end

    logic [31:0] pc, pc_next;
    // logic [63:0] order, order_next;
    logic [ROB_BITS-1:0] tag, tag_next;
    logic        push_to_buffer;
    logic        pop_from_buffer;
    logic        fifo_empty;
    logic        fifo_full;
    instr_t fifo_inst;
    logic jalr_stall, jalr_wake;
    logic [ROB_BITS-1:0] jalr_stall_wb_tag;
    assign jalr_wake = (jalr_stall && jalr_valid && jalr_stall_wb_tag == jalr_wb_tag);

    logic do_pop;
    logic do_push;
    logic [31:0] ras_out;
    logic [31:0] offset, pf_offset;
    assign offset    = pc - dfp_addr_buf;
    assign pf_offset = pc - pf_addr_buf;

    assign buffered    = (offset    < 32 && offset    >= 0);
    assign pf_buffered = (pf_offset < 32 && pf_offset >= 0) && pf_valid;

    assign imem_valid = buffered | (pf_buffered & pf_valid);

    always_comb begin
        fifo_inst.word = fetch_rdata;
        if (buffered)
            fifo_inst.word = dfp_rdata_buf[{offset[4:2],   5'b0} +: 32];
        else if (pf_buffered & pf_valid)
            fifo_inst.word = pf_rdata_buf[{pf_offset[4:2], 5'b0} +: 32];
    end

    // assign order_next = order + 64'd1;
    assign tag_next = tag + {{(ROB_BITS-2){1'b0}}, 1'b1};


//  fifo/ if->id logic

    assign push_to_buffer  =  imem_valid && !flush && !fifo_full && !jalr_stall;
    assign pop_from_buffer = !flush && !fifo_empty && !global_stall;

    if_id_reg_t  if_id_reg, if_id_reg_read; 

    fifo fifo_buffer(
      .clk        (clk),
      .rst        (rst),
      .data_in    (if_id_reg),
      .push       (push_to_buffer),
      .data_out   (if_id_reg_read), 
      .pop        (pop_from_buffer),
      .queue_full (fifo_full),
      .queue_empty(fifo_empty),
      .clear      (flush)
    );

    assign if_id_reg.valid     = push_to_buffer;
    assign if_id_reg.pc        = pc;
    assign if_id_reg.pc_next   = pc_next;
    assign if_id_reg.inst = fifo_inst;
    assign if_id_reg.tag     = tag;
    assign fetch_addr = pc;

    always_comb begin
        if (~pop_from_buffer)
            if_id_reg_out = '0;
        else
            if_id_reg_out = if_id_reg_read;
    end


// Branch predictor logic
// BHT (BTB) + Global History + gselect PHT
    bht_entry_t bht [BHT_ENTRIES]; 
    // logic bht_web;
    // logic [5:0] bht_addr;
    // bht_entry_t bht_wdata, bht_rdata;
    // bht bht(.clk0(clk), .csb0('0), .web0(bht_web), .addr0(bht_addr), .din0(bht_wdata), .dout0(bht_rdata));


    logic [SAT_CNTR_BITS-1:0] pht [PHT_ENTRIES]; //holds 2^6 entries of 2 b*t saturating counter bits
    logic [GHT_BITS-1:0] ghr; //holds global history of taken/not taken

    logic [BHT_IDX_BITS-1:0]  idx; 
    logic [BHT_TAG_BITS-1:0] pc_tag;          
    assign idx = pc[BHT_IDX_BITS+1:2]; 
    assign pc_tag = pc[31: 2+BHT_IDX_BITS];


    //allows better hashing with more ght bits and less pht bits
    logic [PHT_IDX_BITS-1:0]    pht_index_pred; 
    logic [PHT_IDX_BITS-1:0] pc_slice, gh_slice;

    assign pc_slice = pc[2 + PHT_IDX_BITS - 1 : 2];
    assign gh_slice = ghr[PHT_IDX_BITS-1:0];    
    assign pht_index_pred   = pc_slice ^ gh_slice;
    
    // Prediction signals
    logic        bht_hit;
    logic        predicted_taken;
    logic [31:0] predicted_target;
    logic [SAT_CNTR_BITS-1:0] pstate;

    always_comb begin
        bht_hit          = 1'b0;
        predicted_taken  = 1'b0;
        predicted_target = pc + 32'd4;
        pc_next          = pc + 32'd4;
        pstate           = pht[pht_index_pred];

        if (bht[idx].valid && bht[idx].is_branch && (bht[idx].tag == pc_tag))begin
            bht_hit          = 1'b1;
            predicted_taken  = pstate[SAT_CNTR_BITS-1];
            predicted_target = bht[idx].target;
            if (predicted_taken) pc_next = predicted_target;
        end
        else if (jalr_wake) begin
            pc_next = jalr_target;
        end
        else if (do_pop) begin
            pc_next = ras_out;
        end
    end


    //update branch predictor logic
    integer i;
    logic [BHT_IDX_BITS-1:0] commit_idx;
    logic [BHT_TAG_BITS-1:0] commit_tag;
    logic commit_taken;

 
    assign commit_idx = br_commit_pc[BHT_IDX_BITS+1:2]; 

    assign commit_tag   = br_commit_pc[31:BHT_IDX_BITS+2];
    assign commit_taken = (br_commit_pc_next != (br_commit_pc + 32'd4));


    logic [PHT_IDX_BITS-1:0]    pht_index_commit;     
    logic [PHT_IDX_BITS-1:0] commit_pc_slice, commit_gh_slice; 

    assign commit_pc_slice = br_commit_pc[2 + PHT_IDX_BITS - 1 : 2]; 
    assign commit_gh_slice = ghr[PHT_IDX_BITS-1:0];
    assign pht_index_commit = commit_pc_slice ^ commit_gh_slice;

    // pc, order, predictor state updates 
    always_ff @(posedge clk) begin
        if (rst) begin
            pc           <= 32'hAAAAA000;
            tag        <= '0;
            prev_buffered <= 1'b1;
            prev_pfb      <= 1'b1;
            jalr_stall   <= 1'b0;

            for (i = 0; i < BHT_ENTRIES; i++) begin //reset logic
                bht[i].valid  <= 1'b0;
                bht[i].tag    <= '0;
                bht[i].target <= 32'h0;
                bht[i].is_branch  <= '0;
            end

            ghr <= '0;
            for (i = 0; i < PHT_ENTRIES; i++) begin
                pht[i] <= {1'b1, {(SAT_CNTR_BITS-1){1'b0}}};
            end

        end else begin
            prev_buffered <= buffered;
            prev_pfb      <= pf_buffered;
            if (flush) begin
                pc         <= flush_pc;
                tag      <= flush_tag + {{(ROB_BITS-2){1'b0}}, 1'b1};
                jalr_stall <= 1'b0;
            end else if (push_to_buffer) begin
                pc    <= pc_next;
                tag <= tag_next;
                if (fifo_inst.i_type.opcode == op_jalr) begin
                    if (do_pop) begin
                        pc <= pc_next;
                    end else begin 
                        jalr_stall        <= 1'b1;
                        jalr_stall_wb_tag <= tag; // bottom N bits of order == wb tag
                    end
                end else begin
                    jalr_stall <= '0;
                end
            end else if (jalr_wake) begin
                jalr_stall <= '0;
                pc         <= pc_next;
            end

            // train predictor on committed branches
            if (br_commit_valid) begin
                // update BTB entry
                bht[commit_idx].is_branch <= '1;
                bht[commit_idx].valid  <= '1;
                bht[commit_idx].tag    <= commit_tag;
                bht[commit_idx].target <= br_commit_pc_next;

                // update PHT counter at gselect index
                if (commit_taken) begin
                    if (pht[pht_index_commit] != '1) 
                        pht[pht_index_commit] <= pht[pht_index_commit] + {{(SAT_CNTR_BITS-1){1'b0}}, 1'b1}; // more "taken"
                end else begin
                    if (pht[pht_index_commit] != '0)
                        pht[pht_index_commit] <= pht[pht_index_commit] - {{(SAT_CNTR_BITS-1){1'b0}}, 1'b1}; // more "not taken"
                end
                ghr <= {ghr[GHT_BITS-2:0], commit_taken}; //update global history with actual outcome
            end
        end
    end


// RAS stuff
    logic ras_push, ras_pop, arc_push, arc_pop;
    logic ras_full, ras_empty;
    logic commit_rd_match, fetch_rd_match, commit_rs1_match, fetch_rs1_match, fetch_eq, commit_eq;
    logic [4:0] commit_rs1, commit_rd, fetch_rs1, fetch_rd;
    assign commit_rs1 = jalr_commit_inst.i_type.rs1;
    assign commit_rd = jalr_commit_inst.i_type.rd;
    assign fetch_rs1 = fifo_inst.i_type.rs1;
    assign fetch_rd = fifo_inst.i_type.rd;

    assign commit_rs1_match = jalr_commit_valid && (commit_rs1 == 5'd1 || commit_rs1 ==  5'd5);
    assign fetch_rd_match = (fifo_inst.i_type.opcode == op_jalr) && push_to_buffer && (fetch_rd == 5'd1 || fetch_rd == 5'd5);
    assign commit_rd_match = jalr_commit_valid && (commit_rd == 5'd1 || commit_rd == 5'd5);
    assign fetch_rs1_match = (fifo_inst.i_type.opcode == op_jalr) && push_to_buffer && (fetch_rs1 == 5'd1 || fetch_rd == 5'd5);
    assign fetch_eq = (fetch_rs1 == fetch_rd);
    assign commit_eq = (commit_rd == commit_rs1);

    assign ras_push = commit_rd_match;
    assign ras_pop = fetch_rs1_match & ~fetch_eq;

    assign arc_push = commit_rd_match;
    assign arc_pop = commit_rs1_match & ~commit_eq;

    logic [ADDR_BITS:0] head_ptr, tail_ptr, top;
    assign top = tail_ptr - 1'b1;

    logic [31:0] ras [RAS_ENTRIES]; //the actual queue

    logic [ADDR_BITS:0] head_ptr_arc, tail_ptr_arc; // architectural (committed) RAS

    logic [31:0] arc_ras [RAS_ENTRIES]; //the actual queue

    assign ras_empty = (head_ptr == tail_ptr);
    assign ras_full = (head_ptr[ADDR_BITS] != tail_ptr[ADDR_BITS]) && (head_ptr[ADDR_BITS-1:0] == tail_ptr[ADDR_BITS-1:0]);
    
    logic [ROB_BITS-1:0] in_flight_calls, in_flight_calls_next;

    always_comb begin
        do_pop  = ras_pop  && !ras_empty && ~(|in_flight_calls); // ret - make sure no calls are in-flight, meaning all calls are already in ras
        do_push = ras_push;  // call
    end

    //initialize fifo
    always_ff @(posedge clk) begin
        if(rst) begin
            head_ptr <= '0;
            tail_ptr <= '0;

        end else if (flush) begin
            head_ptr <= head_ptr_arc;
            tail_ptr <= tail_ptr_arc;
            for (integer i = 0; i < RAS_ENTRIES; i++) ras[i] <= arc_ras[i];
            if(do_push) begin // push even when flushing (when we mispredict a call?)
                ras[tail_ptr_arc[ADDR_BITS-1:0]] <= jalr_commit_rd_v;
                tail_ptr <= tail_ptr_arc + 1'b1; //increment tail after you add data to queue
            end
        end else begin
            if(do_push) begin
                ras[tail_ptr[ADDR_BITS-1:0]] <= jalr_commit_rd_v;
                if (~ras_full) begin 
                    tail_ptr <= tail_ptr + 1'b1; //increment tail after you add data to queue
                end else begin
                    head_ptr <= head_ptr + 1'b1;
                    tail_ptr <= tail_ptr + 1'b1;
                end
            end
            if(do_pop) begin
                tail_ptr <= tail_ptr - 1'b1; //decrement tail
            end
        end
    end
    assign ras_out = ras_empty ? '0 : ras[top[ADDR_BITS-1:0]]; //always return the top of the queue


    logic arc_ras_empty, arc_ras_full, do_pop_arc, do_push_arc;
    assign arc_ras_empty = (head_ptr_arc == tail_ptr_arc);
    assign arc_ras_full = (head_ptr_arc[ADDR_BITS] != tail_ptr_arc[ADDR_BITS]) && (head_ptr_arc[ADDR_BITS-1:0] == tail_ptr_arc[ADDR_BITS-1:0]);
    
    always_comb begin
        do_pop_arc  = arc_pop && !arc_ras_empty;
        do_push_arc = arc_push;
    end

    always_ff @(posedge clk) begin
        if(rst) begin
            in_flight_calls <= '0;
            head_ptr_arc <= '0;
            tail_ptr_arc <= '0;
        end else begin
            in_flight_calls <= in_flight_calls_next;
            if(do_push_arc) begin
                arc_ras[tail_ptr_arc[ADDR_BITS-1:0]] <= jalr_commit_rd_v;
                if (~arc_ras_full) begin 
                    tail_ptr_arc <= tail_ptr_arc + 1'b1; //increment tail after you add data to queue
                end else begin
                    head_ptr_arc <= head_ptr_arc + 1'b1;
                end
            end
            if(do_pop_arc) begin
                tail_ptr_arc <= tail_ptr_arc - 1'b1; //decrement tail
            end
        end
    end

    always_comb begin
        in_flight_calls_next = in_flight_calls;
        if (flush) in_flight_calls_next = '0;
        else begin 
            if (fetch_rd_match) in_flight_calls_next = in_flight_calls_next + 1'b1;
            if (do_push_arc) in_flight_calls_next = in_flight_calls_next - 1'b1;
        end
    end


endmodule : if_stage