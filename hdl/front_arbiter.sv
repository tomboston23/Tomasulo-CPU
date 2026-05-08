module front_arbiter 
import cache_types::*;(
    input  logic        clk,
    input  logic        rst,
    input   logic   [31:0]      icache_addr,
    input   logic               icache_read,
    // input   logic               icache_write,
    // input   logic   [63:0]      icache_wdata,
    output  logic               icache_ready,
    output  logic   [31:0]      icache_raddr,
    output  logic   [63:0]      icache_rdata,
    output  logic               icache_rvalid,

    input   logic   [31:0]      dcache_addr,
    input   logic               dcache_read,
    input   logic               dcache_write,
    input   logic   [63:0]      dcache_wdata,
    output  logic               dcache_ready,
    output  logic   [31:0]      dcache_raddr,
    output  logic   [63:0]      dcache_rdata,
    output  logic               dcache_rvalid,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,
    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid
);

logic use_imem;

imem_input_t imem_input, imem_output;
assign imem_input = {icache_addr, icache_read};
logic buff_full, buff_empty;

always_comb begin
    use_imem = '0;
    icache_rvalid = bmem_rvalid;
    icache_raddr = bmem_raddr;
    icache_rdata = bmem_rdata;

    dcache_raddr = bmem_raddr;
    dcache_rdata = bmem_rdata;
    dcache_rvalid = bmem_rvalid;

    bmem_addr = '0;
    bmem_write = '0;
    bmem_read = '0;
    bmem_wdata = '0;

    // // any dcache signal takes priority 
    if(dcache_read || dcache_write) begin
        icache_ready = 1'b0; 
        bmem_addr = dcache_addr;
        bmem_read = dcache_read;
        bmem_write = dcache_write;
        bmem_wdata = dcache_wdata;
    end
    // else we let icache do stuff
    else begin
        icache_ready = bmem_ready;
        use_imem = '1;
        bmem_write = '0;
        bmem_wdata = '0;
        if (buff_empty & icache_read) begin
            bmem_addr = icache_addr;
            bmem_read = icache_read;
        end else if (~buff_empty) begin
            bmem_addr = imem_output.addr;
            bmem_read = imem_output.read;
        end
    end
    //dcache_ready = bmem_ready;
    dcache_ready = bmem_ready;
end


fifo #(.T(imem_input_t), .ENTRIES(4)) imem_buffer (
    .clk (clk),
    .rst (rst),
    .data_in(imem_input),
    .push(imem_input.read & (~use_imem | ~buff_empty)), // only push if we are stalling imem (using dmem) or there is already something in the buffer
    .data_out(imem_output),
    .pop(use_imem & ~buff_empty),
    .queue_full(buff_full),
    .queue_empty(buff_empty),
    .clear('0)
);

endmodule