`timescale 1ns/1ps

module fifo_tb;
  import cache_types::*;

  // Element type and queue sizing
  localparam type T       = if_id_reg_t;
  localparam int  ENTRIES = 8;   // power of 2
  localparam int  ADDR_BITS  = (ENTRIES <= 1) ? 1 : $clog2(ENTRIES);
  localparam int  PTR_BITS   = ADDR_BITS + 1; // wrap bit + index bits

  // DUT signals
  logic clk;
  logic rst;
  T     data_in;
  logic push;
  logic pop;
  T     data_out;
  logic queue_full;
  logic queue_empty;

  // DUT instance: fifo with type parameter T
  fifo #(
    .T(T),
    .ENTRIES(ENTRIES)
  ) dut (
    .clk, .rst,
    .data_in,
    .push,
    .data_out,
    .pop,
    .queue_full,
    .queue_empty
  );

  // Clock
  initial clk = 1'b0;
  always #5 clk = ~clk; // 100MHz

  // if_id_reg_t (from your package for reference)
  // typedef struct packed {
  //   logic        valid;
  //   logic [31:0] pc;
  //   logic [31:0] pc_next;
  //   logic [31:0] inst;
  //   logic [63:0] order;
  // } if_id_reg_t;

  // >>> You asked for a TASK (not a function):
  // Create a valid if_id_reg_t entry via an output argument.
  task automatic make_if_id_entry(input logic [31:0] count, output if_id_reg_t temp);
    temp.valid  = 1'b1;
    temp.pc     = 32'hAAAA_A000 + count;
    temp.pc_next= temp.pc + 32'd4;
    temp.inst   = 32'hDEAD_BEEF + count; // placeholder instruction
    temp.order  = {32'b0, count};
  endtask

///BEGIN TEST/////
  initial begin
    integer i;
    logic [PTR_BITS-1:0] head_before, tail_before;
    bit stay_full_ok;
    if_id_reg_t gen;  // temp holder for make_if_id_entry

    
    logic head_wrap0, head_wrap1, tail_wrap0, tail_wrap1;
    logic [ADDR_BITS-1:0] head_idx0, tail_idx0, head_idx1, tail_idx1;
    if_id_reg_t gen2;

    //------------------------------
    // Reset check
    //------------------------------
    rst     = 1'b1;
    push    = 1'b0;
    pop     = 1'b0;
    data_in = '0;

    @(posedge clk);
    @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    $display("[t=%0t] After reset: empty=%0d full=%0d head=%0d tail=%0d",
             $time, queue_empty, queue_full, dut.head_ptr, dut.tail_ptr);

    if (queue_empty && !queue_full)
      $display("PASS: Reset -> empty=1, full=0");
    else begin
      $display("FAIL: Reset flags wrong (empty=%0d full=%0d)", queue_empty, queue_full);
      $fatal(1);
    end

    //------------------------------
    // Fill to full (enqueue structs)
    //------------------------------
    $display("\n[Fill] Pushing %0d items...", ENTRIES);
    for (i = 0; i < ENTRIES; i++) begin
      @(negedge clk);
      make_if_id_entry(i, gen);
      data_in = gen;
      push    = 1'b1;
      pop     = 1'b0;
      @(posedge clk);
      push = 1'b0;
      $display("[t=%0t] push=%0d pop=%0d din=%p dout=%p empty=%0d full=%0d head=%0d tail=%0d",
               $time, push, pop, data_in, data_out, queue_empty, queue_full, dut.head_ptr, dut.tail_ptr);
    end
    #1;

    if (queue_full && !queue_empty)
      $display("PASS: Fill -> full=1, empty=0");
    else begin
      $display("FAIL: Fill did not reach full (empty=%0d full=%0d head=%0d tail=%0d)",
               queue_empty, queue_full, dut.head_ptr, dut.tail_ptr);
      $fatal(1);
    end

    //------------------------------
    // Extra push while full (should be ignored)
    //------------------------------
    head_before = dut.head_ptr;
    tail_before = dut.tail_ptr;

    @(negedge clk);
    make_if_id_entry(32'hFEED_F00D, gen);
    data_in = gen;
    push    = 1'b1;
    pop     = 1'b0;
    @(posedge clk);
    push = 1'b0;

    #1;
    if ((dut.head_ptr == head_before) && (dut.tail_ptr == tail_before) && queue_full)
      $display("PASS: Extra push while full ignored (no pointer movement).");
    else begin
      $display("FAIL: Extra push while full changed pointers! head %0d->%0d tail %0d->%0d",
               head_before, dut.head_ptr, tail_before, dut.tail_ptr);
      $fatal(1);
    end

    //------------------------------
    // Drain queue completely
    //------------------------------
    $display("\n[Drain] Popping %0d items...", ENTRIES);
    for (i = 0; i < ENTRIES; i++) begin
      @(negedge clk);
      $display("[t=%0t] About to pop: dout=%p head=%0d tail=%0d",
               $time, data_out, dut.head_ptr, dut.tail_ptr);
      push = 1'b0;
      pop  = 1'b1;
      @(posedge clk);
      pop  = 1'b0;
      $display("[t=%0t] After pop: empty=%0d full=%0d head=%0d tail=%0d",
               $time, queue_empty, queue_full, dut.head_ptr, dut.tail_ptr);
    end

    #1;
    if (queue_empty && !queue_full)
      $display("PASS: Drain -> empty=1, full=0");
    else begin
      $display("FAIL: Drain did not reach empty (empty=%0d full=%0d)", queue_empty, queue_full);
      $fatal(1);
    end

    //------------------------------
    // Wrap-around behavior (enqueue structs)
    //------------------------------
    $display("\n[Wrap] Push %0d, Pop %0d, Push %0d (wrap)",
             ENTRIES/2, ENTRIES/4, ENTRIES);

    for (i = 0; i < ENTRIES/2; i++) begin
      @(negedge clk);
      make_if_id_entry(32'h1000_0000 + i, gen);
      data_in = gen;
      push    = 1'b1; pop = 1'b0;
      @(posedge clk);
      push = 1'b0;
    end
    for (i = 0; i < ENTRIES/4; i++) begin
      @(negedge clk);
      push = 1'b0; pop = 1'b1;
      @(posedge clk);
      pop = 1'b0;
    end
    head_before = dut.head_ptr;
    tail_before = dut.tail_ptr;
    for (i = 0; i < ENTRIES; i++) begin
      @(negedge clk);
      make_if_id_entry(32'h2000_0000 + i, gen);
      data_in = gen;
      push    = 1'b1; pop = 1'b0;
      @(posedge clk);
      push = 1'b0;
    end

    #1;
    if ((dut.head_ptr != head_before) || (dut.tail_ptr != tail_before))
      $display("PASS: Wrap sequence moved pointers (wrap bit or index changed).");
    else begin
      $display("FAIL: Wrap sequence did not move pointers.");
      $fatal(1);
    end

    //------------------------------
    // Push+Pop same cycle while full (structs)
    //------------------------------
    $display("\n[Push+Pop same cycle @FULL]");

    // Ensure full
    while (!queue_full) begin
      @(negedge clk);
      make_if_id_entry(32'hE000_0000, gen);
      data_in = gen;
      push    = 1'b1; pop = 1'b0;
      @(posedge clk);
      push = 1'b0;
    end

    stay_full_ok = 1'b1;
    for (i = 0; i < 4; i++) begin
      @(negedge clk);
      make_if_id_entry(32'hE000_0000 + i, gen);
      data_in = gen;
      push    = 1'b1;
      pop     = 1'b1; // same cycle
      @(posedge clk);
      push = 1'b0;
      pop  = 1'b0;
      if (!queue_full) stay_full_ok = 1'b0;
    end

    #1;
    if (stay_full_ok)
      $display("PASS: Push+Pop same-cycle kept queue FULL across iterations.");
    else begin
      $display("FAIL: Queue lost FULL during push+pop same-cycle sequence.");
      $fatal(1);
    end

    //add the circular buffer test right HERE. 
        // ============ CIRCULAR / WRAP-AROUND TEST (added) ============
    $display("\n[CIRCULAR] Start wrap verification. state: head=%0b tail=%0b empty=%0d full=%0d",
            dut.head_ptr, dut.tail_ptr, queue_empty, queue_full);

    // Ensure queue is EMPTY first (don’t rely on prior tests’ end-state)
    while (!queue_empty) begin
      pop = '1;
      #1;
      pop = '0;
      #1;
    end
    $display("[CIRCULAR] Emptied. head=%0b tail=%0b empty=%0d full=%0d",
            dut.head_ptr, dut.tail_ptr, queue_empty, queue_full);

    // Snapshot starting wrap bits/indices
    head_wrap0 = dut.head_ptr[ADDR_BITS];
    tail_wrap0 = dut.tail_ptr[ADDR_BITS];
    head_idx0  = dut.head_ptr[ADDR_BITS-1:0];
    tail_idx0  = dut.tail_ptr[ADDR_BITS-1:0];
    $display("[CIRCULAR] Snap0: head_wrap=%0b tail_wrap=%0b head_idx=%0d tail_idx=%0d",
            head_wrap0, tail_wrap0, head_idx0, tail_idx0);

    // --- Tail wrap: push ENTRIES from empty ---

    for (i = 0; i < ENTRIES; i++) begin
      make_if_id_entry(32'd9000 + i, gen2);
      data_in = gen2; push = 1'b1; pop = 1'b0;
      @(posedge clk);
      push = '0;
      $display("FILLING FIFO: head = %0d, tail = %0d, fifo_val = %0d", 
              dut.head_ptr, dut.tail_ptr, dut.do_push, dut.do_pop, dut.fifo[dut.tail_ptr[ADDR_BITS-1:0]]);
      @(posedge clk);
    end


    tail_wrap1 = dut.tail_ptr[ADDR_BITS];
    head_idx1  = dut.head_ptr[ADDR_BITS-1:0];
    tail_idx1  = dut.tail_ptr[ADDR_BITS-1:0];
    $display("[CIRCULAR] After ENTRIES pushes: head=%0b tail=%0b empty=%0d full=%0d",
            dut.head_ptr, dut.tail_ptr, queue_empty, queue_full);
    $display("[CIRCULAR] Tail wrap check: tail_wrap %0b->%0b, head_idx=%0d tail_idx=%0d",
            tail_wrap0, tail_wrap1, head_idx1, tail_idx1);

    if (queue_full && (tail_wrap1 == ~tail_wrap0) && (tail_idx1 == head_idx1))
    $display("PASS: Tail wrapped after ENTRIES pushes (wrap toggled, indices equal, full=1).");
    else begin
    $display("FAIL: Tail wrap failed. full=%0d  tail_wrap %0b->%0b  head_idx=%0b tail_idx=%0b",
            queue_full, tail_wrap0, tail_wrap1, head_idx1, tail_idx1);
    $fatal(1);
    end

    // --- Head wrap: pop ENTRIES from full ---
    for (i = 0; i < ENTRIES; i++) begin
      push = 1'b0; pop = 1'b1;
      @(posedge clk);
      pop = 1'b0;
      @(posedge clk);
    end

    head_wrap1 = dut.head_ptr[ADDR_BITS];
    $display("[CIRCULAR] After ENTRIES pops: head=%0d tail=%0d empty=%0d full=%0d",
            dut.head_ptr, dut.tail_ptr, queue_empty, queue_full);
    $display("[CIRCULAR] Head wrap check: head_wrap %0b->%0b", head_wrap0, head_wrap1);

    if (queue_empty && (head_wrap1 == ~head_wrap0))
      $display("PASS: Head wrapped after ENTRIES pops (wrap toggled, empty=1).");
    else begin
      $display("FAIL: Head wrap failed. empty=%0d  head_wrap %0b->%0b",
              queue_empty, head_wrap0, head_wrap1);
      $fatal(1);
    end
// ========== END CIRCULAR / WRAP-AROUND TEST ==========


    //------------------------------
    // ALL DONE
    //------------------------------
    $display("\nALL FIFO CHECKS PASSED!!!");
    $finish;
  end

endmodule