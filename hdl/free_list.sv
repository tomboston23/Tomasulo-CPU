module free_list 
import cache_types::*;
(
    input logic clk, rst,
    input logic push,         //flag to tell us we need to rename
    input logic pop,           //flag to tell us to free an entry
    output logic [PRF_BITS-1:0] data_out,       //current free entry to output (newly renamed)
    output logic queue_empty,
    input logic clear
);
    logic [PRF_BITS:0] head_ptr, tail_ptr;

    logic queue_full;

    assign queue_empty = (head_ptr == (tail_ptr));
    assign queue_full = (head_ptr[PRF_BITS] != tail_ptr[PRF_BITS]) && (head_ptr[PRF_BITS-1:0] == tail_ptr[PRF_BITS-1:0]);
    
    
    logic do_pop;
    logic do_push;
    always_comb begin
        do_pop  = pop  && !queue_empty;
        do_push = push && (!queue_full || do_pop); //allows for simultaneous pop and push
    end

    //initialize fifo
    logic [31:0] idx;
    always_ff @(posedge clk) begin
        if(rst | clear) begin
            head_ptr <= '0;
            tail_ptr <= {1'b1, {(PRF_BITS){1'b0}}};
        end else begin
            if(do_push) begin
                // no need to actually push data because it should just
                tail_ptr <= tail_ptr + 1'b1; //increment tail after you add data to queue
            end
            if(do_pop) begin
                head_ptr <= head_ptr + 1'b1; //increment head
            end
        end
    end
    assign data_out = queue_empty ? 'x : head_ptr[PRF_BITS-1:0];
endmodule