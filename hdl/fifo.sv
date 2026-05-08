module fifo
import cache_types::*;
#(
  parameter type T = if_id_reg_t,  
  parameter ENTRIES = 16 //make sure this is a power of 2
) 
(
    input logic clk,
    input logic rst,
    input T data_in,
    input logic push, //needs to be high when you enqueue the incoming data
    output T data_out, //will always be the top of the list,
    input logic pop, //pops top off the queue
    output logic queue_full, //is high when the queue is full
    output logic queue_empty, //is high when the queue is empty,
    input logic clear
);
    localparam ADDR_BITS = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES);

    logic [ADDR_BITS:0] head_ptr, tail_ptr;

    T fifo [ENTRIES]; //the actual queue

    assign queue_empty = (head_ptr == (tail_ptr));
    assign queue_full = (head_ptr[ADDR_BITS] != tail_ptr[ADDR_BITS]) && (head_ptr[ADDR_BITS-1:0] == tail_ptr[ADDR_BITS-1:0]);
    
    
    logic do_pop;
    logic do_push;
    always_comb begin
        do_pop  = pop  && !queue_empty;
        do_push = push && (!queue_full || do_pop); //allows for simultaneous pop and push
    end

    //initialize fifo
    always_ff @(posedge clk) begin
        if(rst | clear) begin
            head_ptr <= '0;
            tail_ptr <= '0;
        end else begin
            if(do_push) begin
                fifo[tail_ptr[ADDR_BITS-1:0]] <= data_in;
                tail_ptr <= tail_ptr + 1'b1; //increment tail after you add data to queue
            end
            if(do_pop) begin
                head_ptr <= head_ptr + 1'b1; //increment head
            end
        end
    end
    assign data_out = queue_empty ? '0 : fifo[head_ptr[ADDR_BITS-1:0]]; //always return the top of the queue
endmodule