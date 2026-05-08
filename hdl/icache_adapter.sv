module icache_adapter // cache adapter module with nlp
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

    output  logic   [255:0]     pf_rdata,
    output  logic   [31:0]      pf_addr_out,
    output  logic   prefetch_valid,

    // Dram side
    output  logic   [31:0]      cache_addr,
    output  logic               cache_read,
    output  logic               cache_write,
    output  logic   [63:0]      cache_wdata,
    input   logic               cache_ready,
    input   logic   [31:0]      cache_raddr,
    input   logic   [63:0]      cache_rdata,
    input   logic               cache_rvalid

);
    logic   [63:0]      data_buf[4], data_buf_flop[4], pdata_buf[4], pdata_buf_flop[4];
    logic   [1:0]       idx; 



    logic   [31:0]      pf_addr, fetch_addr;
    logic fetching, prefetching, fetch_resp;
    assign fetching = (cache_raddr == fetch_addr) & cache_rvalid & ~prefetching;
    assign prefetching = (cache_raddr == pf_addr) & cache_rvalid;
    assign fetch_addr = dfp_addr;

    logic read, ready, pf_read, fetch_read; // ready should go high after idx hits 3

    always_ff @(posedge clk) begin
        if (rst) begin
            idx <= '0;
            data_buf_flop[0] <= '0;
            data_buf_flop[1] <= '0;
            data_buf_flop[2] <= '0;
            data_buf_flop[3] <= '0;
        end
        // checks  for both read/write
        else if ((dfp_read && fetching) || (cache_ready && dfp_write)) begin
            idx <= idx+1'b1;
            data_buf_flop[0] <= data_buf[0];
            data_buf_flop[1] <= data_buf[1];
            data_buf_flop[2] <= data_buf[2];
            data_buf_flop[3] <= data_buf[3];
        end else if (prefetching) begin
            idx <= idx+1'b1;
            pdata_buf_flop[0] <= pdata_buf[0];
            pdata_buf_flop[1] <= pdata_buf[1];
            pdata_buf_flop[2] <= pdata_buf[2];
            pdata_buf_flop[3] <= pdata_buf[3];
        end
    end

    // if memory is ready block reads to let the write request proceed
    logic pf_ready, pf_resp;

    always_ff @(posedge clk) begin 
        if (rst) begin 
            read <= '0;
            ready <= '1;
            pf_read <= '0;
            pf_ready <= '0;
            pf_addr <= '0;
        end 
        else if(dfp_read && cache_ready && ~prefetching) begin
            read <= '0;
            ready <= '0;
        end else begin
            read <= '1;
        end
        if (pf_resp) begin
            pf_ready <= '1;
            ready <= '1;
        end
        else if (pf_read) pf_ready <= '0;
        pf_read <= fetch_read;
        if (fetch_read)
            pf_addr <= fetch_addr + 'd32;
    end

    logic prefetched;
    assign prefetched = pf_ready && dfp_read && (dfp_addr == pf_addr);
    assign dfp_resp = (prefetched & dfp_read) | fetch_resp;
    // assign pf_addr_out = (pf_ready | pf_resp) ? prefetch_addr : '0;
    assign prefetch_valid = (pf_ready | pf_resp) & ~pf_read;
    assign pf_rdata = {pdata_buf[3], pdata_buf[2], pdata_buf[1], pdata_buf[0]};
    assign pf_addr_out = pf_addr;
    
    always_comb begin
        data_buf[0] = data_buf_flop[0];
        data_buf[1] = data_buf_flop[1];
        data_buf[2] = data_buf_flop[2];
        data_buf[3] = data_buf_flop[3];
        pdata_buf[0] = pdata_buf_flop[0];
        pdata_buf[1] = pdata_buf_flop[1];
        pdata_buf[2] = pdata_buf_flop[2];
        pdata_buf[3] = pdata_buf_flop[3];
        if (fetching)
            data_buf[idx] = cache_rdata;

        if (prefetching)
            pdata_buf[idx] = cache_rdata;

        fetch_read = dfp_read && read && ready && ~prefetching;
        cache_write = dfp_write;

        if (fetch_read & ~prefetched) begin
            cache_read = '1;
            cache_addr = fetch_addr;
        end else if (pf_read) begin
            cache_read = '1;
            cache_addr = pf_addr;
        end else begin
            cache_read = '0;
            cache_addr = '0;
        end

        cache_wdata = dfp_wdata[{idx, 6'b0} +:64];
        fetch_resp = (idx==2'b11 && fetching) ? 1'b1 : 1'b0 ; 
        pf_resp = (idx==2'b11 && prefetching) ? 1'b1 : 1'b0;

        if (prefetched) 
            dfp_rdata = {pdata_buf[3], pdata_buf[2], pdata_buf[1], pdata_buf[0]};
        else 
            dfp_rdata = {data_buf[3], data_buf[2], data_buf[1], data_buf[0]};

        // pf_rdata = {pdata_buf[3], pdata_buf[2], pdata_buf[1], pdata_buf[0]};
    end
    
endmodule