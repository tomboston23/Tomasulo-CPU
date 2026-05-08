module rob
import cache_types::*;
(
  input  logic                      clk,
  input  logic                      rst,

  // from dispatch
  input  rob_entry_t          dispatch_in,

  // status
  output logic                      rob_full,
  output logic                      rob_empty,

  // to Commit (peek oldest)
  output rob_entry_t                rob_top,

  // from CDB
  input  cdb_t                      cdb_in,

  output logic flush,
  output rob_to_mem_t rob_to_mem,
  input mem_to_rob_t mem_to_rob,

  //branch predictor training data logic
  output logic                      br_commit_valid,
  output logic [31:0]               br_commit_pc,
  output logic [31:0]               br_commit_pc_next,
  input  logic [31:0]               load_result
);


  assign flush = (rob_top.valid & rob_top.ready & (rob_top.pc_pred != rob_top.pc_next));
  // don't flush on jalrs, since the target is always correct. however we don't set pc_pred
  logic [ROB_BITS-1:0] flush_tag;
  assign flush_tag = rob_top.tag;

  localparam ADDR_BITS = (ROB_ENTRIES <= 1) ? 1 : ROB_BITS;

  rob_entry_t rob_fifo [ROB_ENTRIES];

  logic alloc_ok;
  logic [ADDR_BITS:0] head_ptr, tail_ptr;

  assign rob_empty = (head_ptr == tail_ptr);
  assign rob_full  = (head_ptr[ADDR_BITS] != tail_ptr[ADDR_BITS]) &&
                     (head_ptr[ADDR_BITS-1:0] == tail_ptr[ADDR_BITS-1:0]);

  //helper signals to check top of rob
  logic is_head_store, is_head_valid, is_head_ready, is_head_load;
  assign is_head_store = is_head_valid && rob_fifo[head_ptr[ADDR_BITS-1:0]].is_store;
  assign is_head_valid = !rob_empty && rob_fifo[head_ptr[ADDR_BITS-1:0]].valid;
  assign is_head_ready = !rob_empty && rob_fifo[head_ptr[ADDR_BITS-1:0]].ready;
  assign is_head_load = is_head_valid && rob_fifo[head_ptr[ADDR_BITS-1:0]].is_load;
  

  //push pop logic
  logic do_pop, do_push;
  always_comb begin
    do_pop   = is_head_ready;
    alloc_ok = dispatch_in.valid && (!rob_full || do_pop);
    do_push  = alloc_ok;

    rob_to_mem = '0;
    if((is_head_load || is_head_store) && rob_top.valid && rob_top.i_talked_to_cdb && !is_head_ready) begin
      rob_to_mem.valid = '1;
      rob_to_mem.mem_addr = rob_top.mem_addr;
      rob_to_mem.mem_wdata = rob_top.mem_wdata;
      rob_to_mem.mem_wmask = rob_top.mem_wmask;
      rob_to_mem.mem_rmask = rob_top.mem_rmask;
    end
  end

  // State
  always_ff @(posedge clk) begin
    if (rst) begin
      for (integer i = 0; i<ROB_ENTRIES; i++) rob_fifo[i].valid <= '0;
      head_ptr <= '0;
      tail_ptr <= '0;
    end else if (flush) begin
      tail_ptr <= head_ptr + 1'b1; // set empty, I think it's best we keep tail ptr in place
      head_ptr <= head_ptr + 1'b1; // increment both by 1 because a commit is occurring
      // by keeping tail ptr in place we can make rob_tag == lower bits of order
      for (integer i = 0; i<ROB_ENTRIES; i++) rob_fifo[i].valid <= '0;
    end else begin
        if (cdb_in.wb_valid && rob_fifo[cdb_in.wb_tag].valid) begin
          rob_fifo[cdb_in.wb_tag].rs1_v <= cdb_in.rs1_v;
          rob_fifo[cdb_in.wb_tag].rs2_v <= cdb_in.rs2_v;
          rob_fifo[cdb_in.wb_tag].store_value <= cdb_in.wb_value;

          if (rob_fifo[cdb_in.wb_tag].is_load) begin
            rob_fifo[cdb_in.wb_tag].ready       <= 1'b1;
            rob_fifo[cdb_in.wb_tag].i_talked_to_cdb <= 1'b1;
            rob_fifo[cdb_in.wb_tag].mem_rdata    <= cdb_in.mem_rdata ;
          end else if (rob_fifo[cdb_in.wb_tag].is_store)  begin
              rob_fifo[cdb_in.wb_tag].ready <= 1'b0;
          end else begin
            rob_fifo[cdb_in.wb_tag].ready       <= 1'b1;
          end

          if (|cdb_in.pc_wdata) begin
            rob_fifo[cdb_in.wb_tag].pc_next <= cdb_in.pc_wdata; 
          end

          rob_fifo[cdb_in.wb_tag].mem_addr    <= cdb_in.mem_addr ; 
          rob_fifo[cdb_in.wb_tag].mem_wmask   <= cdb_in.mem_wmask ; 
          rob_fifo[cdb_in.wb_tag].mem_rmask   <= cdb_in.mem_rmask ; 
          rob_fifo[cdb_in.wb_tag].mem_wdata   <= cdb_in.mem_wdata;
          rob_fifo[cdb_in.wb_tag].addr_offset <= cdb_in.addr_offset;
          
        end

        //if head is a load and not ready yet, add dcache data when ready
        if(mem_to_rob.valid && rob_fifo[mem_to_rob.rob_tag].valid &&  rob_fifo[mem_to_rob.rob_tag].is_load) begin
          rob_fifo[mem_to_rob.rob_tag].mem_rdata <= mem_to_rob.mem_rdata; 
          rob_fifo[mem_to_rob.rob_tag].store_value <= load_result; 
          rob_fifo[mem_to_rob.rob_tag].ready <= 1'b1;
          rob_fifo[mem_to_rob.rob_tag].mem_addr <= mem_to_rob.mem_addr;
          rob_fifo[mem_to_rob.rob_tag].rs1_v <= mem_to_rob.rs1_v ; 
          rob_fifo[mem_to_rob.rob_tag].rs2_v <= mem_to_rob.rs2_v ; 
          rob_fifo[mem_to_rob.rob_tag].mem_rmask <= mem_to_rob.mem_rmask;
          
        end

        //if head is store, mark ready when dcache completes the store
        if(mem_to_rob.valid && rob_fifo[mem_to_rob.rob_tag].valid &&  rob_fifo[mem_to_rob.rob_tag].is_store) begin
          rob_fifo[mem_to_rob.rob_tag].ready <= 1'b1;
        end

        // Allocate (push)
        if (do_push) begin
          rob_fifo[tail_ptr[ADDR_BITS-1:0]] <= dispatch_in;
          tail_ptr <= tail_ptr + 1'b1;
        end

        // Commit (pop)
        if (do_pop) begin
          rob_fifo[head_ptr[ADDR_BITS-1:0]] <= '0;
          head_ptr <= head_ptr + 1'b1;
        end
    end
  end

  // Oldest entry to commit
  assign rob_top = rob_fifo[head_ptr[ADDR_BITS-1:0]]; // lowkey removed the empty check and it still works lol.. because everything depends on valid b*t
  // this is useful because rob_top was part of our critical path

  logic head_is_branch;
  assign head_is_branch =
      is_head_valid &&
      rob_fifo[head_ptr[ADDR_BITS-1:0]].instruction.i_type.opcode == op_br;

  assign br_commit_valid    = is_head_ready && head_is_branch;
  assign br_commit_pc       = rob_fifo[head_ptr[ADDR_BITS-1:0]].pc;
  assign br_commit_pc_next  = rob_fifo[head_ptr[ADDR_BITS-1:0]].pc_next;

endmodule