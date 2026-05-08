module cache_adapter // cache adapter from main branch
import cache_types::*;   
( 
    input   logic               clk,
    input   logic               rst,

    // Cache signals 
    input   logic   [31:0]      dfp_addr,
    input   logic               dfp_read,
    input   logic               dfp_write,
    output  logic   [255:0]     dfp_rdata,
    input   logic   [255:0]     dfp_wdata,
    output  logic               dfp_resp,
    input   logic   [31:0]      prefetch_addr,
    output  logic               prefetch_valid,
    output  logic   [255:0]     prefetch_rdata,
    output  logic   [31:0]      prefetch_raddr,

    // Dram side
    output  logic   [31:0]      cache_addr,
    output  logic               cache_read,
    output  logic               cache_write,
    output  logic   [63:0]      cache_wdata,
    input   logic               cache_ready,
    input   logic   [31:0]      cache_raddr,
    input   logic   [63:0]      cache_rdata,
    input   logic               cache_rvalid,

    input   logic  [31:0]       dcache_addr,
    input   logic dcache_write

);
    logic   [63:0]      data_buf[4], data_buf_flop[4];
    logic   [1:0]       idx, w_idx; // keep write index separately
    logic   prefetch, fetch;

    logic read, ready, fetching, prefetching, prefetch_resp, fetch_resp, writing, write_resp; // ready should go high after idx hits 3

    assign fetching = dfp_read && cache_rvalid && (cache_raddr==dfp_addr);
    assign writing = cache_ready && dfp_write;
    logic [31:0] prefetch_addr_flop;
    assign prefetching = (idx == 2'b00) ? (cache_rvalid && cache_raddr == prefetch_addr) & ~fetching : (cache_rvalid && cache_raddr == prefetch_addr_flop) & ~fetching;

    logic prefetched;
    assign prefetched = prefetch_valid && dfp_read && (dfp_addr == prefetch_raddr);
    assign dfp_resp = (prefetched & dfp_read) | fetch_resp | write_resp;

    always_ff @(posedge clk) begin
        if(rst) begin
            prefetch_valid <= '0;
            prefetch_rdata <= '0;
            prefetch_raddr <= '0;
        end else if (prefetch_resp) begin
            prefetch_valid <= '1;
            prefetch_rdata <= dfp_rdata;
            prefetch_raddr <= prefetch_addr_flop;
        end else if ((dcache_write && dcache_addr[31:5] == prefetch_raddr[31:5]) || (cache_write && cache_addr[31:5] == prefetch_raddr[31:5])) begin // invalidate prefetched data
            prefetch_valid <= '0;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            idx <= '0;
            w_idx <= '0;
            data_buf_flop[0] <= '0;
            data_buf_flop[1] <= '0;
            data_buf_flop[2] <= '0;
            data_buf_flop[3] <= '0;
        end
        // checks  for both read/write
        else begin 
            if (fetching) begin
                idx <= idx+1'b1;
                data_buf_flop[0] <= data_buf[0];
                data_buf_flop[1] <= data_buf[1];
                data_buf_flop[2] <= data_buf[2];
                data_buf_flop[3] <= data_buf[3];
            end else if (prefetching) begin
                if (idx == 2'b0) prefetch_addr_flop <= prefetch_addr;
                idx <= idx + 1'b1;
                data_buf_flop[0] <= data_buf[0];
                data_buf_flop[1] <= data_buf[1];
                data_buf_flop[2] <= data_buf[2];
                data_buf_flop[3] <= data_buf[3];
            end else idx <= '0;
            if (writing) begin
                w_idx <= w_idx + 1'b1;
            end
        end
    end

    // if memory is ready block reads to let the write request proceed
    always_ff @(posedge clk) begin 
        if (rst) begin 
            read <= '0;
            ready <= '1;
        end 
        else if(dfp_read && cache_ready) begin
            read <= '0;
            ready <= '0;
        end else begin
            read <= '1;
        end
        if (idx == 2'b11 || prefetched) ready <= '1;
    end


    always_ff @(posedge clk) begin
        if(rst) prefetch <= '0;
        else if (fetch) prefetch <= '1; // prefetch after attempting bmem access
        // don't tie prefetch to cache_write
        else prefetch <= '0;
    end

    assign cache_read = fetch | prefetch;

    always_comb begin
        data_buf[0] = data_buf_flop[0];
        data_buf[1] = data_buf_flop[1];
        data_buf[2] = data_buf_flop[2];
        data_buf[3] = data_buf_flop[3];
        data_buf[idx] = cache_rdata;

        fetch = dfp_read && read && ready;
        cache_write = writing;

        cache_addr = fetch | dfp_write ? dfp_addr : prefetch_addr;
        cache_wdata = dfp_wdata[{w_idx, 6'b0} +:64];
        fetch_resp = (idx==2'b11 && fetching) ? 1'b1 : 1'b0 ; 
        write_resp = (w_idx==2'b11 && writing) ? 1'b1 : 1'b0;
        prefetch_resp = (idx == 2'b11 && prefetching) ? 1'b1 : 1'b0;
        dfp_rdata = {data_buf[3], data_buf[2], data_buf[1], data_buf[0]};
        if (prefetched) dfp_rdata = prefetch_rdata;
    end
    
endmodule