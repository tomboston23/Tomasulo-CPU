// module icache
// import cache_types::*; (
//     input   logic           clk,
//     input   logic           rst,


//     input   logic   [31:0]  ufp_addr,
//     output  logic   [31:0]  ufp_rdata,
//     input   logic   [3:0]   ufp_rmask,
//     output  logic           ufp_resp,
    

//     output  logic   [31:0]  dfp_addr,
//     output  logic           dfp_read,
//     input   logic   [255:0] dfp_rdata,
//     input   logic           dfp_resp,

//     output logic [255:0]    dfp_rdata_buf,
//     output logic [31:0]     dfp_addr_buf,

//     // update pc and line buffer
//     input logic fetch,
//     input logic flush,
//     input logic [31:0] flush_pc
// );

//     localparam WAY = 4;

//     logic        hit_any;
//     logic [1:0]  hit_way;
//     logic [1:0]  lru_victim;
//     logic [31:0] stage1_addr;
//     logic        stage1_valid;

//     logic miss;
//     assign miss = stage1_valid && !hit_any;
    
//     logic stall;
//     assign stall = miss && !dfp_resp;

//     logic [31:0] fetch_addr, fetch_addr_out;
//     logic [31:0] fetch_addr_fwd;      // <<< added to mirror prefetch version
//     logic        push, pop, fifo_empty, fifo_full;
    
//     // Aligned fetch address
//     always_comb begin
//         if (flush)
//             fetch_addr = {flush_pc[31:5], 5'b0};
//         else
//             fetch_addr = {ufp_addr[31:5], 5'b0};
//     end
    
//     assign push = (flush | (fetch & (|ufp_rmask))) &  (fifo_empty | (fetch_addr != fetch_addr_out)) & !fifo_full;
    
//     logic [3:0] rmask ; // we dont use this anymore 
//     assign pop = (ufp_resp | dfp_resp);

//     always_comb begin
//         fetch_addr_fwd = '0;
//         if (push && fifo_empty) begin
//             fetch_addr_fwd = fetch_addr;
//             rmask = '1 ; 
//         end else if (!fifo_empty) begin
//             fetch_addr_fwd = fetch_addr_out;
//             rmask = '1 ; 
//         end
//     end
    
//     fifo #(.T(logic [31:0]), .ENTRIES(8)) icache_buffer (
//         .clk        (clk),
//         .rst        (rst),
//         .data_in    (fetch_addr),
//         .push       (push), 
//         .data_out   (fetch_addr_out),
//         .pop        (pop),
//         .queue_full (fifo_full),
//         .queue_empty(fifo_empty),
//         .clear      (1'b0)
//     );


//     logic [31:0] stage0_addr;
//     logic        stage0_valid;
    
//     always_comb begin
//         stage0_valid = 1'b0;
//         stage0_addr  = '0;
        
//         if (!stall) begin
//             if (push && fifo_empty) begin
//                 // Bypass path where new address directly to SRAM
//                 stage0_addr  = fetch_addr_fwd;
//                 stage0_valid = 1'b1;
//             end else if (!fifo_empty) begin
//                 stage0_addr  = fetch_addr_fwd;
//                 stage0_valid = 1'b1;
//             end
//         end
//     end


//     // 
//     always_ff @(posedge clk) begin
//         if (rst) begin
//             stage1_addr  <= '0;
//             stage1_valid <= 1'b0;
//         end else if (!stall) begin
//             stage1_addr  <= stage0_addr;
//             stage1_valid <= stage0_valid;
//         end else if (dfp_resp) begin
//             stage1_valid <= 1'b0;
//         end
//     end


//     // capture lru victim on miss and hold on allocation
//     logic [1:0]  lru_victim_r;
//     logic        miss_pending;
    
//     always_ff @(posedge clk) begin
//         if (rst) begin
//             lru_victim_r <= '0;
//             miss_pending <= 1'b0;
//         end else if (dfp_resp) begin
//             miss_pending <= 1'b0;
//         end else if (miss && !miss_pending) begin
//             lru_victim_r <= lru_victim;
//             miss_pending <= 1'b1;
//         end
//     end
    

//     logic [1:0] victim_way;
//     assign victim_way = miss_pending ? lru_victim_r : lru_victim;


//     logic        data_csb0   [WAY];
//     logic        data_web0   [WAY];
//     logic [31:0] data_wmask0 [WAY];
//     logic [255:0] data_din0  [WAY];
//     logic [255:0] data_dout0 [WAY];
    
//     logic        tag_csb0    [WAY];
//     logic        tag_web0    [WAY];
//     logic [22:0] tag_din0    [WAY];
//     logic [22:0] tag_dout0   [WAY];
    
//     logic        valid_csb0  [WAY];
//     logic        valid_web0  [WAY];
//     logic        valid_din0  [WAY];
//     logic        valid_dout0 [WAY];
    
//     logic        lru_csb0;
//     logic        lru_web0;
//     logic [2:0]  lru_din0;
//     logic [2:0]  lru_dout0;
   
//     logic [3:0] sram_addr;
//     assign sram_addr = (dfp_resp) ? stage1_addr[8:5] : stage0_addr[8:5];

//     generate 
//         for (genvar i = 0; i < 4; i++) begin : arrays
//             mp_cache_data_array data_array (
//                 .clk0   (clk),
//                 .csb0   (data_csb0[i]),
//                 .web0   (data_web0[i]),
//                 .wmask0 (data_wmask0[i]),
//                 .addr0  (sram_addr),
//                 .din0   (data_din0[i]),
//                 .dout0  (data_dout0[i])
//             );
            
//             mp_cache_tag_array tag_array (
//                 .clk0   (clk),
//                 .csb0   (tag_csb0[i]),
//                 .web0   (tag_web0[i]),
//                 .addr0  (sram_addr),
//                 .din0   (tag_din0[i]),
//                 .dout0  (tag_dout0[i])
//             );
            
//             sp_ff_array valid_array (
//                 .clk0   (clk),
//                 .rst0   (rst),
//                 .csb0   (valid_csb0[i]),
//                 .web0   (valid_web0[i]),
//                 .addr0  (sram_addr),
//                 .din0   (valid_din0[i]),
//                 .dout0  (valid_dout0[i])
//             );
//         end
//     endgenerate
    
//     sp_ff_array #(.WIDTH(3)) lru_array (
//         .clk0   (clk),
//         .rst0   (rst),
//         .csb0   (lru_csb0),
//         .web0   (lru_web0),
//         .addr0  (sram_addr),
//         .din0   (lru_din0),
//         .dout0  (lru_dout0)
//     );

//     // stage 1 = hit detection 
//     always_comb begin
//         hit_any = 1'b0;
//         hit_way = 2'd0;
//         for (integer i = 0; i < WAY; i++) begin
//             if (valid_dout0[i] && (tag_dout0[i] == stage1_addr[31:9])) begin
//                 hit_any = 1'b1;
//                 hit_way = i[1:0];
//             end
//         end
//     end

//     // PLRU victim decode
//     always_comb begin
//         unique casez (lru_dout0)
//             3'b00? : lru_victim = 2'd0;
//             3'b01? : lru_victim = 2'd1;
//             3'b1?0 : lru_victim = 2'd2;
//             3'b1?1 : lru_victim = 2'd3;
//             default: lru_victim = 2'dx;
//         endcase
//     end
    
//     logic [2:0] lru_update;
//     always_comb begin
//         lru_update = lru_dout0;
//         unique case (hit_way)
//             2'd0: begin lru_update[2] = 1'b1; lru_update[1] = 1'b1; end
//             2'd1: begin lru_update[2] = 1'b1; lru_update[1] = 1'b0; end
//             2'd2: begin lru_update[2] = 1'b0; lru_update[0] = 1'b1; end
//             2'd3: begin lru_update[2] = 1'b0; lru_update[0] = 1'b0; end
//         endcase
//     end

//     assign ufp_resp  = stage1_valid && hit_any;
//     assign ufp_rdata = data_dout0[hit_way][32*stage1_addr[4:2] +: 32];

//     assign dfp_addr = {stage1_addr[31:5], 5'b0};
//     assign dfp_read = miss;

//     always_ff @(posedge clk) begin
//         if (rst) begin
//             dfp_rdata_buf <= '0;
//             dfp_addr_buf  <= '0;
//         end else if (dfp_resp) begin
//             dfp_rdata_buf <= dfp_rdata;
//             dfp_addr_buf  <= {stage1_addr[31:5], 5'b0};
//         end else if (ufp_resp) begin
//             dfp_rdata_buf <= data_dout0[hit_way];
//             dfp_addr_buf  <= {stage1_addr[31:5], 5'b0};
//         end
//     end


//     always_comb begin
//         for (integer i = 0; i < WAY; i++) begin
//             data_csb0[i]   = 1'b1;
//             data_web0[i]   = 1'b1;
//             data_wmask0[i] = '0;
//             data_din0[i]   = '0;
//             tag_csb0[i]    = 1'b1;
//             tag_web0[i]    = 1'b1;
//             tag_din0[i]    = '0;
//             valid_csb0[i]  = 1'b1;
//             valid_web0[i]  = 1'b1;
//             valid_din0[i]  = 1'b0;
//         end
//         lru_csb0 = 1'b1;
//         lru_web0 = 1'b1;
//         lru_din0 = '0;

//         if (dfp_resp) begin
//             data_csb0[victim_way]   = 1'b0;
//             data_web0[victim_way]   = 1'b0;
//             data_wmask0[victim_way] = '1;
//             data_din0[victim_way]   = dfp_rdata;
            
//             tag_csb0[victim_way]    = 1'b0;
//             tag_web0[victim_way]    = 1'b0;
//             tag_din0[victim_way]    = stage1_addr[31:9];
            
//             valid_csb0[victim_way]  = 1'b0;
//             valid_web0[victim_way]  = 1'b0;
//             valid_din0[victim_way]  = 1'b1;
//         end

//         else if (stage1_valid && hit_any) begin
//             lru_csb0 = 1'b0;
//             lru_web0 = 1'b0;
//             lru_din0 = lru_update;
            
//             if (stage0_valid) begin
//                 for (integer i = 0; i < WAY; i++) begin
//                     data_csb0[i]  = 1'b0;
//                     tag_csb0[i]   = 1'b0;
//                     valid_csb0[i] = 1'b0;
//                 end
//             end
//         end
//         else if (stall) begin
//             lru_csb0 = 1'b0;
//         end
       
//         else if (stage0_valid) begin
//             for (integer i = 0; i < WAY; i++) begin
//                 data_csb0[i]  = 1'b0;
//                 tag_csb0[i]   = 1'b0;
//                 valid_csb0[i] = 1'b0;
//             end
//             lru_csb0 = 1'b0;
//         end
//     end

// endmodule : icache

module icache
import cache_types::*; (
    input   logic           clk,
    input   logic           rst,


    input   logic   [31:0]  ufp_addr,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [3:0]   ufp_rmask,
    output  logic           ufp_resp,
    

    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    input   logic   [255:0] dfp_rdata,
    input   logic           dfp_resp,

    output logic [255:0]    dfp_rdata_buf,
    output logic [31:0]     dfp_addr_buf,

    // update pc and line buffer
    input logic fetch,
    input logic flush,
    input logic [31:0] flush_pc
);

    localparam WAY = 4;
    localparam S_INDEX = 4;
    localparam SETS = 2**S_INDEX;

    localparam idle  = 2'd0;
    localparam hit   = 2'd1;
    localparam alloc = 2'd2;  

    logic hit_signal;
    assign ufp_resp = hit_signal;
    // Interface structs
    cpu_input_t cpu_input;
    mem_input_t mem_input;

    logic [31:0] fetch_addr, fetch_addr_out, fetch_addr_fwd;
    logic push, fifo_empty;
    assign push = flush | fetch & (|ufp_rmask) && (fetch_addr_out != fetch_addr);

    logic [3:0] rmask;

    always_comb begin
        fetch_addr = '0;
        rmask = '0;
        if (flush)  fetch_addr = {flush_pc[31:5],5'b0};
        else if (fetch) fetch_addr = {ufp_addr[31:5],5'b0};

        fetch_addr_fwd = '0;
        if (push & fifo_empty) begin
            fetch_addr_fwd = fetch_addr; // gets data a cycle early
            rmask = '1;
        end else if (!fifo_empty) begin // prevents overriding prefetching
            fetch_addr_fwd = fetch_addr_out;
            rmask = '1;
            
        end
    end
        
    // Send request to memory (read-only for I-cache)
    always_ff @(posedge clk) begin
        if (rst) begin
            dfp_addr <= '0;
            dfp_read <= '0;
        end else begin
            dfp_addr <= mem_input.addr;
            dfp_read <= mem_input.read;
        end
    end

    // assign dfp_addr = mem_input.addr;
    // assign dfp_read = mem_input.read;

    // line buffer
    logic [255:0] dfp_rdata_buf_next;
    logic [31:0] dfp_addr_buf_next;
    always_ff @(posedge clk) begin
        if (rst) begin
            dfp_rdata_buf <= '0;
            dfp_addr_buf <= '0;
        end else if (dfp_resp) begin // prefetch shouldn't alter lbuf
            dfp_rdata_buf <= dfp_rdata;
            dfp_addr_buf <= dfp_addr;
        end else if (ufp_resp) begin
            dfp_rdata_buf <= dfp_rdata_buf_next;
            dfp_addr_buf <= dfp_addr_buf_next;
        end
    end


    fifo #(.T(logic [31:0]), .ENTRIES(8)) icache_buffer (
        .clk        (clk),
        .rst        (rst),
        .data_in    (fetch_addr),
        .push       (push), 
        .data_out   (fetch_addr_out),
        .pop        (ufp_resp | dfp_resp),
        .queue_full (),
        .queue_empty(fifo_empty),
        .clear('0)
    );
    
    logic data_csb0   [WAY];
    logic data_web0   [WAY];
    logic [31:0] data_wmask0 [WAY];
    logic [255:0] data_din0  [WAY];
    logic [255:0] data_dout0 [WAY];
    
    logic tag_csb0    [WAY];
    logic tag_web0    [WAY];
    logic [22:0] tag_din0  [WAY];
    logic [22:0] tag_dout0 [WAY];
    
    logic valid_csb0  [WAY];
    logic valid_web0  [WAY];
    logic valid_din0  [WAY];
    logic valid_dout0 [WAY];
    
    // no dirty array
    
    logic lru_csb0;
    logic lru_web0;
    logic [2:0] lru_din0;
    logic [2:0] lru_dout0;
    
    logic [1:0] lru_decode;
    
    // Array instances
    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_csb0[i]),
            .web0       (data_web0[i]),
            .wmask0     (data_wmask0[i]),
            .addr0      (cpu_input.addr[8:5]),
            .din0       (data_din0[i]),
            .dout0      (data_dout0[i])
        );
        
        mp_cache_tag_array tag_array (
            .clk0   (clk),
            .csb0   (tag_csb0[i]),
            .web0   (tag_web0[i]),
            .addr0  (cpu_input.addr[8:5]),
            .din0   (tag_din0[i]),
            .dout0  (tag_dout0[i])
        );
        
        sp_ff_array valid_array (
            .clk0   (clk),
            .rst0   (rst),
            .csb0   (valid_csb0[i]),
            .web0   (valid_web0[i]),
            .addr0  (cpu_input.addr[8:5]),
            .din0   (valid_din0[i]),
            .dout0  (valid_dout0[i])
        );
    end endgenerate
    
    sp_ff_array #(
        .WIDTH(3)
    ) lru_array (
        .clk0   (clk),
        .rst0   (rst),
        .csb0   (lru_csb0),
        .web0   (lru_web0),
        .addr0  (cpu_input.addr[8:5]),
        .din0   (lru_din0),
        .dout0  (lru_dout0)
    );
    
    // PLRU logic
    always_comb begin
        unique casez (lru_dout0)
            3'b00? : lru_decode = 2'd0;
            3'b01? : lru_decode = 2'd1;
            3'b1?0 : lru_decode = 2'd2;
            3'b1?1 : lru_decode = 2'd3;
            default: lru_decode = 'x;
        endcase
    end
    
    // FSM
    logic [1:0] state, state_next;
    
    always_ff @(posedge clk) begin
        if (rst) state <= idle;
        else state <= state_next;
    end
    
 
    always_comb begin
        cpu_input.addr = {fetch_addr_fwd[31:5], 5'b0};
        cpu_input.r_mask = rmask;
        cpu_input.w_mask = '0;  // No writes in I-cache
        cpu_input.w_data = '0;  // No writes in I-cache
        state_next = state;
        hit_signal = '0;
 
        for (integer i = 0; i < WAY; i++) begin
            data_csb0[i]   = 1'b1;
            data_web0[i]   = 1'b1;
            data_wmask0[i] = '0;
            data_din0[i]   = '0;
            
            tag_csb0[i]    = 1'b1;
            tag_web0[i]    = 1'b1;
            tag_din0[i]    = '0;
            
            valid_csb0[i]  = 1'b1;
            valid_web0[i]  = 1'b1;
            valid_din0[i]  = 1'b0;
            // removed dirty
        end
        
        lru_csb0  = 1'b1;
        lru_web0  = 1'b1;
        lru_din0  = '0;
        
        mem_input.addr = '0;
        mem_input.read = '0;
        mem_input.write = '0;  // Never write in I-cache
        mem_input.w_data = '0; // Never write in I-cache
        ufp_rdata = '0;

        dfp_rdata_buf_next = '0;
        dfp_addr_buf_next = '0;
        
        unique case (state)
            idle: begin
                if (cpu_input.r_mask != 4'b0) begin
                    state_next = hit;
                    
                    // Enable all arrays for reading
                    for (integer i = 0; i < WAY; i++) begin
                        tag_csb0[i]    = 1'b0;
                        data_csb0[i]   = 1'b0;
                        valid_csb0[i]  = 1'b0;
                    end
                    
                    lru_csb0  = 1'b0;
                end
            end
            
            hit: begin
                
                // Check for hit in any way
                for (integer unsigned i = 0; i < WAY; i++) begin
                    
                    if (valid_dout0[i] && tag_dout0[i] == cpu_input.addr[31:9]) begin
                        hit_signal = 1'b1;
                        state_next = idle;
                        
                        
                        // Update LRU
                        lru_csb0  = 1'b0;
                        lru_web0  = 1'b0;
                        lru_din0  = lru_dout0;
                        
                        unique case (i)
                            0: begin lru_din0[2] = 1'b1; lru_din0[1] = 1'b1; end
                            1: begin lru_din0[2] = 1'b1; lru_din0[1] = 1'b0; end
                            2: begin lru_din0[2] = 1'b0; lru_din0[0] = 1'b1; end
                            3: begin lru_din0[2] = 1'b0; lru_din0[0] = 1'b0; end
                            default: lru_din0 = 'x;
                        endcase

                        // Read hit - provide data
                        ufp_rdata = data_dout0[i][32*cpu_input.addr[4:2] +: 32];
                        // load line buffer on hit 
                        dfp_rdata_buf_next = data_dout0[i];
                        dfp_addr_buf_next = {cpu_input.addr[31:5], 5'b0}; // 32B align
                        
                        break;
                    end
                end
                
                // read miss so fetch from memory
                if (!hit_signal) begin
                    state_next = alloc;
                    mem_input.addr = {cpu_input.addr[31:5], 5'b0};
                    mem_input.read = 1'b1;
                    mem_input.write = 1'b0;  // No writes in I-cache
                end
            end
            
            alloc: begin
                lru_csb0 = 1'b0;
                lru_web0 = 1'b1;
                
                mem_input.addr = {cpu_input.addr[31:5], 5'b0};
                mem_input.read = 1'b1;
                mem_input.write = 1'b0;  // No writes in I-cache
                
                if (dfp_resp) begin
                    // Allocate in victim way
                    valid_csb0[lru_decode]  = 1'b0;
                    valid_web0[lru_decode]  = 1'b0;
                    valid_din0[lru_decode]  = 1'b1;
                    
                    data_csb0[lru_decode]   = 1'b0;
                    data_web0[lru_decode]   = 1'b0;
                    data_wmask0[lru_decode] = '1;
                    data_din0[lru_decode]   = dfp_rdata;
                    
                    tag_csb0[lru_decode]    = 1'b0;
                    tag_web0[lru_decode]    = 1'b0;
                    tag_din0[lru_decode]    = cpu_input.addr[31:9];
                    
                    state_next = idle;
                    
                    // Clear memory request
                    mem_input.addr = '0;
                    mem_input.read = '0;
                    mem_input.write = '0;
                    mem_input.w_data = '0;
                end
            end
            
            default: state_next = idle;
        endcase
    end

endmodule : icache