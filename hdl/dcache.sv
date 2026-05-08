module dcache 
import cache_types::*;
    (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,
    output  logic   [31:0]  prefetch_addr,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);

// local params 
localparam WAY = 4 ; 
localparam S_INDEX = 4 ; 
localparam SETS = 2**S_INDEX;
localparam idle  = 2'd0;
localparam hit   = 2'd1;
localparam wb    = 2'd2;
localparam alloc = 2'd3;
logic [1:0] state, state_next;
logic hit_signal ; 

logic [31:0] prev_addr, stride, hit_rdata, ms_pf_addr; // for calculating stride


// logic [255:0] dfp_rdata_buf, dfp_rdata_buf_next;
// logic [31:0] dfp_raddr_buf, dfp_raddr_buf_next; // linebuff and fifo stuff
logic fifo_empty, use_stride;
// logic [31:0] buff_rdata;

assign ufp_resp = hit_signal;


cpu_input_t cpu_input ; 
mem_input_t mem_input ; 
// I removed cpu output and mem output, they were completely useless

// add dcache fifo
cpu_input_t fifo_input, fifo_output;
always_comb begin
    fifo_input = '0;
    fifo_input.addr = ufp_addr;
    fifo_input.r_mask = ufp_rmask;
    fifo_input.w_mask = ufp_wmask;
    fifo_input.w_data = ufp_wdata;

    // assign ufp_rdata
    ufp_rdata = '0;
    // if (buffered) ufp_rdata = buff_rdata;
    if (hit_signal) ufp_rdata = hit_rdata;
end


fifo #(.T(cpu_input_t), .ENTRIES(8)) dcache_buffer (
    .clk(clk),
    .rst(rst),
    .data_in    (fifo_input),
    .push       ((|fifo_input.r_mask) | (|fifo_input.w_mask)), 
    .data_out   (fifo_output),
    .pop        (hit_signal),
    .queue_full (),
    .queue_empty(fifo_empty),
    .clear('0)
);



assign cpu_input = (((|fifo_input.r_mask) | (|fifo_input.w_mask)) & fifo_empty) ? fifo_input : fifo_output;
// cpu-input gets forwarded input if the fifo is empty
    

// 3. Latch input and output responses w ff on clock edges (1-cycle latency ?)
always_ff @ (posedge clk) begin 
    if (rst) begin 
        prev_addr <= '0;
        // pushed <= '0;
        stride <= '0;
    end else begin 
        if ((|fifo_input.r_mask) | (|fifo_input.w_mask)) begin
            // pushed <= '1;
            if (prev_addr == 0) begin
                stride <= 32'd32; // if uninitialized, just do next line prefetch
                prev_addr <= fifo_input.addr; 
            end else if (fifo_input.addr[31:5] != prev_addr[31:5]) begin
                stride <= fifo_input.addr - prev_addr;
                prev_addr <= fifo_input.addr; // only update prev addr if not in same cache line
            end
        end
    end
end

// assign buffered = buffer_valid && (|cpu_input.r_mask & cpu_input.addr[31:5] == dfp_raddr_buf[31:5]);
// assign buff_rdata = buffered ? dfp_rdata_buf[32*cpu_input.addr[4:2] +: 32] : '0;
assign use_stride = ~(|stride[31:20]) | (&stride[31:20]);
assign ms_pf_addr = use_stride ? prev_addr + stride : prev_addr + 'd32;
assign prefetch_addr = {ms_pf_addr[31:5], 5'b0};

// 4. Send request to dfp
always_ff @ (posedge clk) begin 
    if (rst) begin 
        dfp_addr <= '0 ;
        dfp_read <= '0 ; 
        dfp_write <= '0 ; 
        //dfp_rdata <= 
        // dfp_wdata <= '0 ; 
        // dfp_rdata_buf <= '0;
        // dfp_raddr_buf <= '0;
        // buffer_valid <= '0; 
    
    end else begin 
        dfp_addr <= mem_input.addr ;
        dfp_read <= mem_input.read ; 
        dfp_write <= mem_input.write ; 
        //dfp_rdata <= 
        dfp_wdata <= mem_input.w_data; 
        // if((hit_signal && |cpu_input.r_mask) || (state == alloc && dfp_resp)) begin // on read hit or allocate
        //     dfp_rdata_buf <= dfp_rdata_buf_next;
        //     dfp_raddr_buf <= dfp_raddr_buf_next;
        //     buffer_valid <= '1;
        // end else if (hit_signal && |cpu_input.w_mask && cpu_input.addr[31:5] == dfp_raddr_buf[31:5]) begin // invalidate
        //     // I think we can come up with a way to make it update lbuf if it hits
        //     dfp_raddr_buf <= dfp_raddr_buf_next;
        //     dfp_rdata_buf <= dfp_rdata_buf_next;
        //     // buffer_valid <= '0;
        // end
        // // end else if (hit_signal && |cpu_input.w_mask && cpu_input.addr[31:5] == prefetch_raddr[31:5])
    end
end

   

//6. set up array signals 
logic data_csb0   [WAY];   //  ts  is active low 
logic data_web0   [WAY];   // active low we    
logic [31:0] data_wmask0 [WAY]; // active high we will be ignored if web is deasserted
logic [S_INDEX-1:0] data_addr0 [WAY];  
logic [255:0] data_din0  [WAY];  
logic [255:0] data_dout0 [WAY];  

logic tag_csb0    [WAY];
logic tag_web0    [WAY];
logic [S_INDEX-1:0] tag_addr0 [WAY];
logic [22:0] tag_din0  [WAY];   
logic [22:0] tag_dout0 [WAY];

logic valid_csb0  [WAY];
logic valid_web0  [WAY];
logic [S_INDEX-1:0] valid_addr0 [WAY];
logic valid_din0  [WAY];
logic valid_dout0 [WAY];

logic dirty_csb0  [WAY];
logic dirty_web0  [WAY];
logic [S_INDEX-1:0] dirty_addr0 [WAY];
logic dirty_din0  [WAY];
logic dirty_dout0 [WAY];

logic lru_csb0;
logic lru_web0;
logic [S_INDEX-1:0] lru_addr0;
logic [2:0] lru_din0;
logic [2:0] lru_dout0;

// the victim way output from plru 
logic [1:0] lru_decode;




// creating 4 instances of each data tag valid and dirty array
    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_csb0[i]),
            .web0       (data_web0[i]),
            .wmask0     (data_wmask0[i]),
            .addr0      (data_addr0[i]),
            .din0       (data_din0[i]),
            .dout0      (data_dout0[i])
        );
        mp_cache_tag_array tag_array (
            .clk0   (clk),
            .csb0   (tag_csb0[i]),
            .web0   (tag_web0[i]),
            .addr0  (tag_addr0[i]),
            .din0   (tag_din0[i]),
            .dout0  (tag_dout0[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0   (valid_csb0[i]),
            .web0   (valid_web0[i]),
            .addr0  (valid_addr0[i]),
            .din0   (valid_din0[i]),
            .dout0  (valid_dout0[i])
        );

        sp_ff_array dirty_array (
            .clk0   (clk),
            .rst0   (rst),
            .csb0   (dirty_csb0[i]),
            .web0   (dirty_web0[i]),
            .addr0  (dirty_addr0[i]),
            .din0   (dirty_din0[i]),
            .dout0  (dirty_dout0[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (lru_csb0),
        .web0       (lru_web0),
        .addr0      (lru_addr0),
        .din0       (lru_din0),
        .dout0      (lru_dout0)
    );

// PLRU 
always_comb begin 
    unique casez (lru_dout0)   
    3'b00? : lru_decode = 2'd0; //root = 0 left = 0 -> w0 is victim
    3'b01? : lru_decode = 2'd1; // root = 0 letf = 1 -> w1 is victim 
    3'b1?0 : lru_decode = 2'd2; 
    3'b1?1 : lru_decode = 2'd3;
    default: lru_decode = 'x ; 
    endcase
end

//FSM
always_ff @ (posedge clk) begin 
    if (rst) state <= idle ;
    else state <= state_next ;
end 

always_comb begin 
    state_next = state; 
    hit_rdata = '0;
    // dfp_raddr_buf_next = dfp_raddr_buf;
    // dfp_rdata_buf_next = dfp_rdata_buf;
    hit_signal = '0; 
    for( integer i = 0; i < WAY; i++) begin 
        data_csb0[i]   = 1'b1;     // disable data array
        data_web0[i]   = 1'b1;     // read mode (not writing)
        data_addr0[i]  = '0;       // no valid address
        data_wmask0[i] = '0;       // no bytes enabled
        data_din0[i]   = '0;       // no data to write

        tag_csb0[i]   = 1'b1;      // disable tag array
        tag_web0[i]   = 1'b1;      // read mode
        tag_addr0[i]  = '0;
        tag_din0[i]   = '0;

        valid_csb0[i]  = 1'b1;    
        valid_web0[i]  = 1'b1;     // read mode
        valid_addr0[i] = '0;
        valid_din0[i]  = 1'b0;

        dirty_csb0[i]  = 1'b1;
        dirty_web0[i]  = 1'b1;
        dirty_addr0[i] = '0;
        dirty_din0[i]  = 1'b0;

    end

    lru_csb0   = 1'b1;  
    lru_web0   = 1'b1;  
    lru_addr0  = '0;
    lru_din0   = '0;

    mem_input.addr  = '0 ; 
    mem_input.read  = '0 ;
    mem_input.write = '0 ;
    mem_input.w_data = '0 ; 

   unique case (state)
        idle: begin
            if ((cpu_input.r_mask != 4'b0) || (cpu_input.w_mask != 4'b0)) begin // don't bother going through cache if line buffer hit
                state_next = hit;

                // present set index to all ways
                for (integer i = 0; i < WAY; i++) begin
                    tag_addr0[i]   = cpu_input.addr[8:5];
                    data_addr0[i]  = cpu_input.addr[8:5];
                    valid_addr0[i] = cpu_input.addr[8:5];
                    dirty_addr0[i] = cpu_input.addr[8:5];
                    tag_csb0[i]    = 1'b0;
                    data_csb0[i]   = 1'b0;
                    valid_csb0[i]  = 1'b0;
                    dirty_csb0[i]  = 1'b0;
                end
                lru_addr0 = cpu_input.addr[8:5];
                lru_csb0  = 1'b0;
            end
        end

        hit: begin
            for (integer unsigned i = 0; i < WAY; i++) begin
                tag_addr0[i]   = cpu_input.addr[8:5];
                data_addr0[i]  = cpu_input.addr[8:5];
                valid_addr0[i] = cpu_input.addr[8:5];
                lru_addr0      = cpu_input.addr[8:5];

                if (valid_dout0[i] && tag_dout0[i] == cpu_input.addr[31:9]) begin
                    // Cache hit
                    hit_signal           = 1'b1;
                    state_next           = idle;

                    // Update LRU bits
                    lru_csb0 = 1'b0;
                    lru_web0 = 1'b0;
                    lru_addr0 = cpu_input.addr[8:5];
                    lru_din0 = lru_dout0;

                    unique case (i)
                        0: begin lru_din0[2] = 1'b1; lru_din0[1] = 1'b1; end
                        1: begin lru_din0[2] = 1'b1; lru_din0[1] = 1'b0; end
                        2: begin lru_din0[2] = 1'b0; lru_din0[0] = 1'b1; end
                        3: begin lru_din0[2] = 1'b0; lru_din0[0] = 1'b0; end
                        default: lru_din0 = 'x;
                    endcase

                    // Write hit
                    if (|cpu_input.w_mask) begin
                        dirty_csb0[i]  = 1'b0 ;
                        dirty_web0[i]  = 1'b0;
                        dirty_addr0[i] = cpu_input.addr[8:5];
                        dirty_din0[i]  = 1'b1;
                        data_csb0[i]   = 1'b0;
                        data_web0[i]   = 1'b0;
                        data_addr0[i]  = cpu_input.addr[8:5];
                        data_wmask0[i][4*cpu_input.addr[4:2] +: 4] = cpu_input.w_mask;
                        data_din0[i][32*cpu_input.addr[4:2] +: 32] = cpu_input.w_data;
                        // write to line buffer
                        // if (cpu_input.w_mask[0])
                        //     dfp_rdata_buf_next[32*cpu_input.addr[4:2] +: 8] = cpu_input.w_data[7:0];
                        // if (cpu_input.w_mask[1])
                        //     dfp_rdata_buf_next[(32*cpu_input.addr[4:2] + 8) +: 8] = cpu_input.w_data[15:8];
                        // if (cpu_input.w_mask[2])
                        //     dfp_rdata_buf_next[(32*cpu_input.addr[4:2] + 16) +: 8] = cpu_input.w_data[23:16];
                        // if (cpu_input.w_mask[3])
                        //     dfp_rdata_buf_next[(32*cpu_input.addr[4:2] + 24) +: 8] = cpu_input.w_data[31:24];
                    end
                    // Read hit
                    else if (|cpu_input.r_mask) begin
                        hit_rdata = data_dout0[i][32*cpu_input.addr[4:2] +: 32];
                        // dfp_rdata_buf_next = data_dout0[i];
                    end

                    
                    // dfp_raddr_buf_next = {cpu_input.addr[31:5], 5'b0};

                    break; // stop loop after a hit
                end
            end

            // Miss so we choose victim and go to WB or ALLOC
            if (~hit_signal) begin
                lru_addr0 = cpu_input.addr[8:5];

                if (dirty_dout0[lru_decode] && valid_dout0[lru_decode]) begin
                    state_next = wb;
                    mem_input.addr   = {tag_dout0[lru_decode], cpu_input.addr[8:5], 5'b0};
                    mem_input.write  = 1'b1;
                    mem_input.read   = 1'b0;
                    mem_input.w_data = data_dout0[lru_decode];
                end else begin
                    state_next = alloc;
                    mem_input.addr   = {cpu_input.addr[31:9], cpu_input.addr[8:5], 5'b0};
                    mem_input.write  = 1'b0;
                    mem_input.read   = 1'b1;
                end
            end
        end
        wb: begin
            lru_csb0 = 1'b0;
            lru_web0 = 1'b1;
            lru_addr0 = cpu_input.addr[8:5];


            tag_addr0[lru_decode]  = cpu_input.addr[8:5];
            data_addr0[lru_decode] = cpu_input.addr[8:5];

            mem_input.addr   = {tag_dout0[lru_decode], cpu_input.addr[8:5], 5'b0};
            mem_input.write  = 1'b1;
            mem_input.read   = 1'b0;
            mem_input.w_data = data_dout0[lru_decode];

            if (dfp_resp) begin
                state_next = alloc;
                mem_input.addr   = {cpu_input.addr[31:9], cpu_input.addr[8:5], 5'b0};
                mem_input.write  = 1'b0;
                mem_input.read   = 1'b1;
            end else begin 
                state_next = wb;
            end 
        end
        alloc: begin
            lru_csb0 = 1'b0;
            lru_web0 = 1'b1;
            lru_addr0 = cpu_input.addr[8:5];

            mem_input.addr   = {cpu_input.addr[31:9], cpu_input.addr[8:5], 5'b0};
            mem_input.write  = 1'b0;
            mem_input.read   = 1'b1;

            if (dfp_resp) begin
                // Update valid, dirty, tag, and data
                valid_csb0[lru_decode] = 1'b0;
                valid_web0[lru_decode] = 1'b0;
                valid_addr0[lru_decode] = cpu_input.addr[8:5];
                valid_din0[lru_decode] = 1'b1;

                dirty_csb0[lru_decode] = 1'b0;
                dirty_web0[lru_decode] = 1'b0;
                dirty_addr0[lru_decode] = cpu_input.addr[8:5];
                dirty_din0[lru_decode] = 1'b0;

                data_csb0[lru_decode] = 1'b0;
                data_web0[lru_decode] = 1'b0;
                data_addr0[lru_decode] = cpu_input.addr[8:5];
                data_wmask0[lru_decode] = '1; // entire line
                data_din0[lru_decode] = dfp_rdata;

                tag_csb0[lru_decode] = 1'b0;
                tag_web0[lru_decode] = 1'b0;
                tag_addr0[lru_decode] = cpu_input.addr[8:5];
                tag_din0[lru_decode] = cpu_input.addr[31:9];

                // dfp_rdata_buf_next = dfp_rdata;
                // dfp_raddr_buf_next = {cpu_input.addr[31:5], 5'b0};

                state_next = idle;

                mem_input.addr   = '0;
                mem_input.write  = '0;
                mem_input.read   = '0;
                mem_input.w_data = '0;
            end
        end
        default: state_next = idle;

    endcase

end 

endmodule