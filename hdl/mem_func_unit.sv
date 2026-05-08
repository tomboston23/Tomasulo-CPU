module mem_func_unit
import cache_types::*;
#(
    parameter DEPTH = 8
)
(
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    
    // Allocation interface (from dispatch)
    input  logic                    lsq_alloc_valid,
    input  logic                    lsq_alloc_is_load,
    input  logic                    lsq_alloc_is_store,
    input  logic [ROB_BITS-1:0]     lsq_alloc_rob_tag,
    // input  logic [63:0]             lsq_alloc_order,
    input  logic [31:0]             lsq_alloc_inst,
    input  logic [PRF_BITS:0]       lsq_alloc_dest_preg,
    
    // From reservation station (address resolution)
    input  rs_entry_t   rs_entry_mem,
    
    // To CDB
    output cdb_t        fu_result_mem,

    
    // From ROB
    input  logic [ROB_BITS-1:0] rob_head_tag,
    
    // To D-cache
    output logic [31:0] dcache_addr,
    output logic [31:0] dcache_wdata,
    output logic [3:0]  dcache_wmask,
    output logic [3:0]  dcache_rmask,
    input  logic [31:0] dcache_rdata,
    input  logic        dcache_resp,
    
    // To ROB
    output mem_to_rob_t mem_to_rob,
    
    // Backpressure
    output logic        lsq_ld_full,
    output logic        lsq_st_full,
    output logic        lsq_full,
    // input  logic        mem_fu_buffer_full,
    
    // CDB input (for store data ready marking)
    // input  cdb_t        cdb_output,
    input  logic    [ROB_BITS-1:0] commit_tag
);


    localparam IDX_BITS = $clog2(DEPTH);
    typedef logic [IDX_BITS-1:0] mem_func_idx_t;

    logic lq_full, lq_has_ready;
    logic [IDX_BITS-1:0] lq_alloc_idx;
    logic [IDX_BITS-1:0] lq_ready_idx;
    logic [31:0] k_logic;
    logic [31:0] k_logic2;
    logic [ROB_BITS-1:0] lq_age, sq_age;

    assign lsq_ld_full = lq_full;

    // Store Queue FIFO pointers
    logic [IDX_BITS:0]   sq_head, sq_tail;
    logic [IDX_BITS-1:0] sq_head_idx, sq_tail_idx;
    assign sq_head_idx = sq_head[IDX_BITS-1:0];
    assign sq_tail_idx = sq_tail[IDX_BITS-1:0];
    
    logic sq_empty, sq_full_internal;
    assign sq_empty = (sq_head == sq_tail);
    assign sq_full_internal = (sq_head[IDX_BITS] != sq_tail[IDX_BITS]) &&
                              (sq_head_idx == sq_tail_idx);
    assign lsq_st_full = sq_full_internal;

    // Combined full signal
    assign lsq_full = (lsq_alloc_is_load && lq_full) || (lsq_alloc_is_store && lsq_st_full);


    lq_entry_t load_queue  [DEPTH];
    sq_entry_t store_queue [DEPTH];

    // Load Queue FIFO pointers
    // logic [IDX_BITS:0]   lq_head, lq_tail;
    // logic [IDX_BITS-1:0] lq_head_idx, lq_tail_idx;
    // assign lq_head_idx = lq_head[IDX_BITS-1:0];
    // assign lq_tail_idx = lq_tail[IDX_BITS-1:0];

    always_comb begin
        lq_full = '1;
        lq_alloc_idx = '0;
        k_logic = '0;
        // lq_has_ready = '0;
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            k_logic = 32'(i);
            // lq_age = load_queue[i].rob_tag - commit_tag;
            // if (load_queue[i].valid && load_queue[i].addr_ready && lq_age < sq_age) begin
            //     lq_has_ready = '1;
            //     lq_ready_idx = k_logic[IDX_BITS-1:0];
            // end
            if (!load_queue[i].valid) begin
                lq_full = '0;
                lq_alloc_idx = k_logic[IDX_BITS-1:0];
                break;
            end
        end 
    end

    always_comb begin
        // lq_full = '1;
        lq_has_ready = '0;
        lq_ready_idx = '0;
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            k_logic2 = 32'(i);
            lq_age = load_queue[i].rob_tag - commit_tag;
            if (load_queue[i].valid && load_queue[i].addr_ready && !load_queue[i].issued && (sq_empty || lq_age < sq_age)) begin
                lq_has_ready = '1;
                lq_ready_idx = k_logic2[IDX_BITS-1:0];
                break;
            end
            // else if (!load_queue[i].valid) begin
            //     lq_full = '0;
            //     lq_alloc_idx = k_logic[IDX_BITS-1:0];
            // end
        end 
    end
    // logic lq_empty, lq_full_internal;
    // assign lq_empty = (lq_head == lq_tail);
    // assign lq_full_internal = (lq_head[IDX_BITS] != lq_tail[IDX_BITS]) &&
    //                           (lq_head_idx == lq_tail_idx);

    // counter used to check validity of data post branch taken 
    logic [1:0] count; 
    logic [1:0] count_inflight; 
    always_ff @(posedge clk) begin 
        if (rst) count <= '0; 
        else if (flush) count <= count + 1'b1; 
    end 

    // Head entries for easy access
    // lq_entry_t lq_head_entry;
    sq_entry_t sq_head_entry;
    // assign lq_head_entry = load_queue[lq_head_idx];
    assign sq_head_entry = store_queue[sq_head_idx];

    // address calculation
    logic [31:0] immediate, effective_addr, aligned_addr;
    logic [1:0]  addr_offset;
    logic [3:0]  wmask, rmask;
    logic [31:0] shifted_wdata;
    
    always_comb begin
        if (rs_entry_mem.is_load) begin
            immediate = {{21{rs_entry_mem.inst.word[31]}}, rs_entry_mem.inst.word[30:20]};
        end else begin
            immediate = {{21{rs_entry_mem.inst.word[31]}},rs_entry_mem.inst.word[30:25],rs_entry_mem.inst.word[11:7]};
        end
        
        effective_addr = rs_entry_mem.src1_value + immediate;
        aligned_addr   = {effective_addr[31:2], 2'b00};
        addr_offset    = effective_addr[1:0];
        
        rmask = '0;
        wmask = '0;
        
        if (rs_entry_mem.is_load) begin
            unique case (rs_entry_mem.inst.i_type.funct3)
                lw:      rmask = 4'b1111;
                lh, lhu: rmask = 4'b0011 << {addr_offset[1], 1'b0};
                lb, lbu: rmask = 4'b0001 << addr_offset;
                default: rmask = '0;
            endcase
        end else if (rs_entry_mem.is_store) begin
            unique case (store_funct3_t'(rs_entry_mem.inst.word[14:12]))
                sw: wmask = 4'b1111;
                sh: wmask = 4'b0011 << {addr_offset[1], 1'b0};
                sb: wmask = 4'b0001 << addr_offset;
                default: wmask = '0;
            endcase
        end
        
        shifted_wdata = rs_entry_mem.src2_value << (8 * addr_offset);
    end

    logic alloc_load, alloc_store;
    assign alloc_load  = lsq_alloc_valid && lsq_alloc_is_load  && !lsq_ld_full ;
    assign alloc_store = lsq_alloc_valid && lsq_alloc_is_store && !lsq_st_full ;

    logic resolve_load, resolve_store;
    assign resolve_load  = rs_entry_mem.valid && rs_entry_mem.is_load ;
    assign resolve_store = rs_entry_mem.valid && rs_entry_mem.is_store ;

    // Need to search FIFO for matching rob_tag + order
    logic                found_load_resolve;
    logic [IDX_BITS-1:0] load_resolve_idx;
    logic [31:0] i_logic;
    
    always_comb begin
        found_load_resolve = 1'b0;
        load_resolve_idx = '0;
        
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            i_logic = 32'(i);
            if (load_queue[i].valid &&
                !load_queue[i].addr_ready &&
                load_queue[i].rob_tag == rs_entry_mem.dest_tag
                //load_queue[i].age == rs_entry_mem.order && 
               // load_queue[i].inst == rs_entry_mem.inst.word
               ) begin
                found_load_resolve = 1'b1;
                load_resolve_idx = i_logic[IDX_BITS-1:0];
                break;
            end
        end
    end
    
    // Find a store entry that needs to be resolved 
    logic                found_store_resolve;
    logic [IDX_BITS-1:0] store_resolve_idx;
    logic [31:0] j_logic;
    
    always_comb begin
        found_store_resolve = 1'b0;
        store_resolve_idx = '0;
        
        for (integer unsigned i = 0; i < DEPTH; i++) begin
            j_logic = 32'(i);
            if (store_queue[i].valid &&
                !store_queue[i].data_ready &&
                store_queue[i].rob_tag == rs_entry_mem.dest_tag
               // store_queue[i].age == rs_entry_mem.order
               ) begin
                found_store_resolve = 1'b1;
                store_resolve_idx = j_logic[IDX_BITS-1:0];
                break;
            end
        end
    end

    logic                inflight_valid;
    logic                inflight_is_load;
    logic [IDX_BITS-1:0] inflight_idx;
    lq_entry_t           inflight_load_entry;
    sq_entry_t           inflight_store_entry;

   
    // // A load may issue only if the load is ready and id no older store is unresolved and if no older store has the same address
    
    // logic load_has_older_store;
    // logic load_can_issue;
    // logic [ROB_BITS-1:0] sq_age, lq_age;
    // assign lq_age = lq_head_entry.rob_tag - commit_tag; // tells us how many instructions away from commit this load is
    assign sq_age = sq_head_entry.rob_tag - commit_tag;
    // assign load_has_older_store = (!sq_empty && sq_head_entry.valid && sq_age < lq_age);
    
    // Gate issue signals with !flush to prevent issuing NEW transactions on flush cycle
    // assign load_can_issue = !lq_empty && lq_head_entry.valid && 
    //     lq_head_entry.addr_ready && !lq_head_entry.issued && !inflight_valid && !flush;


    logic store_can_issue;
    assign store_can_issue = !sq_empty && sq_head_entry.valid && sq_head_entry.data_ready &&
        sq_head_entry.committed &&!sq_head_entry.issued && !inflight_valid && !flush;

    // Give priority to stores 
    logic issue_load, issue_store;
    assign issue_store = store_can_issue;
    assign issue_load  = lq_has_ready && !store_can_issue && !inflight_valid && !flush;

    logic [31:0] dcache_addr_reg, dcache_addr_reg_debug;
    assign dcache_addr_reg_debug = (issue_load) ? load_queue[lq_ready_idx].addr : '0;
    logic [31:0] dcache_wdata_reg;
    logic [3:0]  dcache_wmask_reg;
    logic [3:0]  dcache_rmask_reg, dcache_rmask_reg_debug;
    assign dcache_rmask_reg_debug = (issue_load) ? load_queue[lq_ready_idx].rmask : '0;

    always_ff @(posedge clk) begin
        if (rst) begin
            dcache_addr_reg  <= '0;
            dcache_wdata_reg <= '0;
            dcache_wmask_reg <= '0;
            dcache_rmask_reg <= '0;
        end else if (issue_load) begin
            dcache_addr_reg  <= load_queue[lq_ready_idx].addr;
            dcache_wdata_reg <= '0;
            dcache_rmask_reg <= load_queue[lq_ready_idx].rmask;
            dcache_wmask_reg <= '0;
        end else if (issue_store) begin
            dcache_addr_reg  <= sq_head_entry.addr;
            dcache_wdata_reg <= sq_head_entry.data;
            dcache_wmask_reg <= sq_head_entry.wmask;
            dcache_rmask_reg <= '0;
        end else if (inflight_valid) begin
            // NEED these clear signals do notr delete 
            dcache_addr_reg  <= '0;
            dcache_wdata_reg <= '0;
            dcache_wmask_reg <= '0;
            dcache_rmask_reg <= '0;
        end
    end


    always_comb begin
        dcache_addr = '0;
        dcache_wdata = '0;
        dcache_wmask = '0;
        dcache_rmask = '0;
        if (issue_store) begin
            dcache_addr = sq_head_entry.addr;
            dcache_wmask = sq_head_entry.wmask;
            dcache_wdata = sq_head_entry.data;
        end else if (issue_load) begin
            dcache_addr = load_queue[lq_ready_idx].addr;
            dcache_rmask = load_queue[lq_ready_idx].rmask;
        end
    end

    // Load result processing
    logic [31:0] load_result;
    logic [1:0]  load_addr_offset;
    assign load_addr_offset = inflight_load_entry.addr_offset;
    
    always_comb begin
        load_result = dcache_rdata;
        
        if (dcache_resp && inflight_valid && inflight_is_load) begin
            unique case (inflight_load_entry.inst[14:12])
                3'b000:  // LB
                    load_result = {{24{dcache_rdata[7 + 8*load_addr_offset]}},
                                   dcache_rdata[8*load_addr_offset +: 8]};
                3'b100:  // LBU
                    load_result = {24'b0, dcache_rdata[8*load_addr_offset +: 8]};
                3'b001:  // LH
                    load_result = {{16{dcache_rdata[15 + 16*load_addr_offset[1]]}},
                                   dcache_rdata[16*load_addr_offset[1] +: 16]};
                3'b101:  // LHU
                    load_result = {16'b0, dcache_rdata[16*load_addr_offset[1] +: 16]};
                default: // LW
                    load_result = dcache_rdata;
            endcase
        end
    end

    // Completion signals - ONLY valid when epoch matches (filters stale responses)
    logic load_complete, store_complete;
    assign load_complete  = dcache_resp && inflight_valid && inflight_is_load && (count_inflight == count);
    assign store_complete = dcache_resp && inflight_valid && !inflight_is_load && (count_inflight == count);

    // Signal for when we get ANY response (valid or stale) - used to clear inflight
    logic any_response;
    assign any_response = dcache_resp && inflight_valid;

    // Stores broadcast on CDB when addr_ready && data_ready
    logic                store_needs_cdb;
    logic [IDX_BITS-1:0] store_cdb_idx;
    sq_entry_t           store_cdb_entry;
    always_comb begin
        store_needs_cdb = 1'b0;
        store_cdb_idx = '0;
        store_cdb_entry = '0;
        
        // Find oldest store that needs CDB broadcast
        if (sq_head_entry.valid && sq_head_entry.data_ready && !sq_head_entry.cdb_sent) begin
            store_needs_cdb = '1;
            store_cdb_idx = sq_head_idx;
            store_cdb_entry = sq_head_entry;
        end
    end
    
    // Gate CDB broadcast with !flush - don't broadcast to CDB during flush
    logic store_cdb_broadcast;
    assign store_cdb_broadcast = store_needs_cdb && !load_complete && !flush;

    // CDB output
    always_comb begin
        fu_result_mem = '0;
        
        if (load_complete) begin
            fu_result_mem.wb_valid        = 1'b1;
            fu_result_mem.wb_tag          = inflight_load_entry.rob_tag;
            fu_result_mem.wb_physical_reg = inflight_load_entry.dest_preg;
            fu_result_mem.wb_value        = load_result;
            //fu_result_mem.order           = inflight_load_entry.age;
            fu_result_mem.rs1_v           = inflight_load_entry.rs1_v;
            fu_result_mem.rs2_v           = inflight_load_entry.rs2_v;
            fu_result_mem.inst.word       = inflight_load_entry.inst;
            fu_result_mem.is_a_load       = 1'b1;
            fu_result_mem.mem_addr        = inflight_load_entry.addr;
            fu_result_mem.mem_rmask       = inflight_load_entry.rmask;
            fu_result_mem.mem_rdata       = dcache_rdata;
            fu_result_mem.addr_offset     = inflight_load_entry.addr_offset;
            // fu_result_mem.misaligned_mem_addr = inflight_load_entry.addr_unaligned;
        end else if (store_cdb_broadcast) begin
            fu_result_mem.wb_valid        = 1'b1;
            fu_result_mem.wb_tag          = store_cdb_entry.rob_tag;
            fu_result_mem.wb_physical_reg = store_cdb_entry.dest_preg;
            fu_result_mem.wb_value        = '0;
            //fu_result_mem.order           = store_cdb_entry.age;
            fu_result_mem.rs1_v           = store_cdb_entry.rs1_v;
            fu_result_mem.rs2_v           = store_cdb_entry.rs2_v;
            fu_result_mem.inst.word       = store_cdb_entry.inst;
            fu_result_mem.is_a_load       = 1'b0;
            fu_result_mem.mem_addr        = store_cdb_entry.addr;
            fu_result_mem.mem_wmask       = store_cdb_entry.wmask;
            fu_result_mem.mem_wdata       = store_cdb_entry.data;
            fu_result_mem.addr_offset     = store_cdb_entry.addr_offset;
            // fu_result_mem.misaligned_mem_addr = store_cdb_entry.addr_unaligned;
        end
    end

    // Populate mem_to_rob
    always_comb begin
        mem_to_rob = '0;
        
        if (load_complete) begin
            mem_to_rob.valid               = 1'b1;
            mem_to_rob.rob_tag             = inflight_load_entry.rob_tag;
            mem_to_rob.is_load             = 1'b1;
            mem_to_rob.is_store            = 1'b0;
            //mem_to_rob.order               = inflight_load_entry.age;
            mem_to_rob.mem_addr            = inflight_load_entry.addr;
            // mem_to_rob.misaligned_mem_addr = inflight_load_entry.addr_unaligned;
            mem_to_rob.addr_offset         = inflight_load_entry.addr_offset;
            mem_to_rob.rs1_v               = inflight_load_entry.rs1_v;
            mem_to_rob.rs2_v               = inflight_load_entry.rs2_v;
            mem_to_rob.load_data           = load_result;
            mem_to_rob.mem_rmask           = inflight_load_entry.rmask;
            mem_to_rob.mem_rdata           = dcache_rdata;
            mem_to_rob.inst                = inflight_load_entry.inst;
            mem_to_rob.mem_resp            = 1'b1;
        end else if (store_complete) begin
            mem_to_rob.valid               = 1'b1;
            mem_to_rob.rob_tag             = inflight_store_entry.rob_tag;
            mem_to_rob.is_load             = 1'b0;
            mem_to_rob.is_store            = 1'b1;
            //mem_to_rob.order               = inflight_store_entry.age;
            mem_to_rob.mem_addr            = inflight_store_entry.addr;
            // mem_to_rob.misaligned_mem_addr = inflight_store_entry.addr_unaligned;
            mem_to_rob.addr_offset         = inflight_store_entry.addr_offset;
            mem_to_rob.rs1_v               = inflight_store_entry.rs1_v;
            mem_to_rob.rs2_v               = inflight_store_entry.rs2_v;
            mem_to_rob.mem_wmask           = inflight_store_entry.wmask;
            mem_to_rob.mem_wdata           = inflight_store_entry.data;
            mem_to_rob.inst                = inflight_store_entry.inst;
            mem_to_rob.mem_resp            = 1'b1;
        end
    end

    
    // Store Commit Detection
    logic                found_store_to_commit;
    logic [IDX_BITS-1:0] store_commit_idx;
    
    // logic [ROB_BITS-1:0] prev_rob_head_tag;
    // logic rob_head_changed;
    
    // always_ff @(posedge clk) begin
    //     if (rst || flush) begin
    //         prev_rob_head_tag <= '0;
    //     end else begin
    //         prev_rob_head_tag <= rob_head_tag;
    //     end
    // end
    
    // assign rob_head_changed = (rob_head_tag != prev_rob_head_tag);
    
    always_comb begin
        found_store_to_commit = 1'b0;
        store_commit_idx = '0;
        
        if (!sq_empty && 
            sq_head_entry.valid &&
            sq_head_entry.rob_tag == rob_head_tag &&
            sq_head_entry.data_ready &&
            sq_head_entry.cdb_sent &&
            !sq_head_entry.committed &&
            !flush) begin
            found_store_to_commit = 1'b1;
            store_commit_idx = sq_head_idx;
        end
    end

    // Inflight transaction tracking
    // Key: On flush, we keep inflight_valid HIGH until we get the response
    // This allows the transaction to complete, but the epoch mismatch
    // will cause the response to be discarded
    always_ff @(posedge clk) begin
        if (rst) begin
            inflight_valid       <= 1'b0;
            inflight_is_load     <= 1'b0;
            inflight_idx         <= '0;
            inflight_load_entry  <= '0;
            inflight_store_entry <= '0;
            count_inflight       <= '0; 
        end else if (flush && !inflight_valid) begin
            // Flush with no inflight transaction - just reset
            inflight_valid       <= 1'b0;
            inflight_is_load     <= 1'b0;
            inflight_idx         <= '0;
            inflight_load_entry  <= '0;
            inflight_store_entry <= '0;
            count_inflight       <= '0;
        end else if (any_response) begin
            // Got a response (valid or stale) - clear inflight
            inflight_valid <= 1'b0;
        end else if (issue_load) begin
            inflight_valid       <= 1'b1;
            inflight_is_load     <= 1'b1;
            inflight_idx         <= lq_ready_idx;
            inflight_load_entry  <= load_queue[lq_ready_idx];
            count_inflight       <= count; 
        end else if (issue_store) begin
            inflight_valid       <= 1'b1;
            inflight_is_load     <= 1'b0;
            inflight_idx         <= sq_head_idx;
            inflight_store_entry <= sq_head_entry;
            count_inflight       <= count; 
        end
        // NOTE: On flush WITH inflight transaction, we keep inflight_valid HIGH
        // and wait for the response. The epoch mismatch will filter it.
    end

    // Queue management
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            // lq_head <= '0;
            // lq_tail <= '0;
            sq_head <= '0;
            sq_tail <= '0;
            for (integer i = 0; i < DEPTH; i++) begin
                load_queue[i]  <= '0;
                store_queue[i] <= '0;
            end
        end else begin
            // Populate load queue 
            if (alloc_load) begin
                load_queue[lq_alloc_idx].valid          <= 1'b1;
                load_queue[lq_alloc_idx].rob_tag        <= lsq_alloc_rob_tag;
                load_queue[lq_alloc_idx].addr           <= '0;
                load_queue[lq_alloc_idx].addr_offset    <= '0;
                load_queue[lq_alloc_idx].addr_ready     <= 1'b0;
                load_queue[lq_alloc_idx].rs1_v          <= '0;
                load_queue[lq_alloc_idx].rs2_v          <= '0;
                load_queue[lq_alloc_idx].rmask          <= '0;
                load_queue[lq_alloc_idx].inst           <= lsq_alloc_inst;
                load_queue[lq_alloc_idx].dest_preg      <= lsq_alloc_dest_preg;
                // load_queue[lq_tail_idx].age            <= lsq_alloc_order;
                load_queue[lq_alloc_idx].issued         <= 1'b0;
                // lq_tail <= lq_tail + 1'b1;
            end
            
            // Populate store queue
            if (alloc_store) begin
                store_queue[sq_tail_idx].valid          <= 1'b1;
                store_queue[sq_tail_idx].rob_tag        <= lsq_alloc_rob_tag;
                store_queue[sq_tail_idx].addr           <= '0;
                store_queue[sq_tail_idx].addr_offset    <= '0;
                // store_queue[sq_tail_idx].addr_ready     <= 1'b0;
                store_queue[sq_tail_idx].data           <= '0;
                store_queue[sq_tail_idx].data_ready     <= 1'b0;
                store_queue[sq_tail_idx].committed      <= 1'b0;
                store_queue[sq_tail_idx].rs1_v          <= '0;
                store_queue[sq_tail_idx].rs2_v          <= '0;
                store_queue[sq_tail_idx].wmask          <= '0;
                store_queue[sq_tail_idx].inst           <= lsq_alloc_inst;
                store_queue[sq_tail_idx].dest_preg      <= lsq_alloc_dest_preg;
                // store_queue[sq_tail_idx].age            <= lsq_alloc_order;
                store_queue[sq_tail_idx].issued         <= 1'b0;
                store_queue[sq_tail_idx].cdb_sent       <= 1'b0;
                sq_tail <= sq_tail + 1'b1;
            end
            
            // Resolve load address
            if (resolve_load && found_load_resolve) begin
                load_queue[load_resolve_idx].addr_ready     <= 1'b1;
                load_queue[load_resolve_idx].addr           <= aligned_addr;
                load_queue[load_resolve_idx].addr_offset <= addr_offset;
                load_queue[load_resolve_idx].rmask          <= rmask;
                load_queue[load_resolve_idx].rs1_v          <= rs_entry_mem.src1_value;
                load_queue[load_resolve_idx].rs2_v          <= rs_entry_mem.src2_value;
            end
 
            if (resolve_store && found_store_resolve) begin
                // store_queue[store_resolve_idx].addr_ready     <= 1'b1;
                store_queue[store_resolve_idx].addr           <= aligned_addr;
                store_queue[store_resolve_idx].addr_offset <= addr_offset;
                store_queue[store_resolve_idx].data           <= shifted_wdata;
                store_queue[store_resolve_idx].data_ready     <= 1'b1;
                store_queue[store_resolve_idx].wmask          <= wmask;
                store_queue[store_resolve_idx].rs1_v          <= rs_entry_mem.src1_value;
                store_queue[store_resolve_idx].rs2_v          <= rs_entry_mem.src2_value;
            end
            
            // Mark store as committed
            if (found_store_to_commit) begin
                store_queue[store_commit_idx].committed <= 1'b1;
            end
            
            // Mark store CDB broadcast complete
            if (store_cdb_broadcast) begin
                store_queue[store_cdb_idx].cdb_sent <= 1'b1;
            end
            
            // Track issue 
            if (issue_load) begin
                load_queue[lq_ready_idx].issued <= 1'b1;
            end
            if (issue_store) begin
                store_queue[sq_head_idx].issued <= 1'b1;
            end
            
            // Complete load - dequeue (only on VALID completion, not stale)
            if (load_complete) begin
                load_queue[inflight_idx] <= '0;
                // lq_head <= lq_head + 1'b1;
            end
            
            // Complete store - dequeue (only on VALID completion, not stale)
            if (store_complete) begin
                store_queue[inflight_idx] <= '0;
                sq_head <= sq_head + 1'b1;
            end
        end
    end

endmodule

