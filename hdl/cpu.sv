module cpu
import cache_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid
);


//signals
    // functional unit signals that its done 
    logic       mult_ready;
    logic       alu_ready;
    logic       memory_ready;
    logic       branch_ready;
    // no alu stall/ br stall needed
    logic       mul_stall;

    logic       clear_alu, clear_muldiv;
    logic clear_br; 
    logic clear_mem ; 
    cdb_t alu_out, mul_div_out, mem_out, br_out;
    cdb_t  cdb_output;
    
    // isssue tells func unit to begin new operation if resources available 
    logic       can_begin_alu, can_begin_br;
    logic       can_begin_mult;
    logic      can_begin_mem;
    rob_entry_t dispatch_to_rob;
    rs_entry_t dispatch_alu_rs, dispatch_mul_rs, dispatch_mem_rs, dispatch_br_rs;
    logic rob_full, rob_empty;

    rob_entry_t rvfi_rob;
    rs_entry_t alu_rs_output, mul_rs_output, br_rs_output, mem_rs_output;
    logic alu_rs_full, mul_rs_full, mem_rs_full, br_rs_full;
    logic mem_ready_rob;


// burst mem -> adaptor -> icache -> fetch -> fifo buff
    logic [31:0]  fetch_addr;   // instruction fetch address
    logic [3:0]   fetch_rmask;  // 
    logic [31:0]  fetch_rdata;  // fetched instruction data
    logic         fetch_resp;   // response (cache hit/ready)

    // ICACHE adapter signals (cache side - 256 )
    logic [31:0]   icache_dfp_addr;
    logic          icache_dfp_read;
    logic          icache_dfp_write;
    logic [255:0]  icache_dfp_rdata;
    logic [255:0]  icache_dfp_wdata;
    logic          icache_dfp_resp;

    // ICACHE adapter signals (memory side - 64)
    logic [31:0]   icache_bmem_addr;
    logic          icache_bmem_read;
    // logic          icache_bmem_write;
    // logic [63:0]   icache_bmem_wdata;
    logic          icache_bmem_ready;
    logic [31:0]   icache_bmem_raddr;
    logic [63:0]   icache_bmem_rdata;
    logic          icache_bmem_rvalid;
    logic          fetch;

    // ICACHE NLP signals
    logic [31:0]   nlp_raddr;
    logic [255:0]  nlp_rdata;
    logic          nlp_valid;


    logic [31:0]   dcache_pf_addr;
    // DCACHE adapter signals (cache side - 256)
    logic [31:0]   dcache_dfp_addr;
    logic          dcache_dfp_read;
    logic          dcache_dfp_write;
    logic [255:0]  dcache_dfp_rdata;
    logic [255:0]  dcache_dfp_wdata;
    logic          dcache_dfp_resp;

    // DCACHE adapter signals (memory side - 64)
    logic [31:0]   dcache_bmem_addr;
    logic          dcache_bmem_read;
    logic          dcache_bmem_write;
    logic [63:0]   dcache_bmem_wdata;
    logic          dcache_bmem_ready;
    logic [31:0]   dcache_bmem_raddr;
    logic [63:0]   dcache_bmem_rdata;
    logic          dcache_bmem_rvalid;

    logic [31:0] dcache_ufp_addr;
    logic [31:0] dcache_rdata;
    logic [31:0] dcache_wdata;
    logic [3:0]  dcache_rmask;
    logic [3:0]  dcache_wmask;
    logic        dcache_ufp_resp;

    mem_to_rob_t mem_to_rob;
    rob_to_mem_t rob_to_mem;

    logic [31:0] lsq_dcache_addr;
    logic [31:0] lsq_dcache_wdata;
    logic [3:0]  lsq_dcache_wmask;
    logic [3:0]  lsq_dcache_rmask;
    logic [31:0]  lsq_dcache_rdata;
    logic        lsq_dcache_resp;
    logic lsq_full ; 


    logic imem_valid, global_stall, dispatch_stall, flush;

 
    assign global_stall = ~imem_valid || rob_full || dispatch_stall;
    // this is stalling forever with rob_full... need to instead make RS read from PRF rather than cdb
    // imem valid comes from fetch
    // no dmem valid because that should not stall globally
    // this only stalls front end (fetch decode dispatch)

    if_id_reg_t  if_id_reg;
    id_dis_reg_t id_dis_reg, id_dis_reg_next;

    
    // add other updates?
    always_ff @(posedge clk)begin
        if (rst | flush) begin
            id_dis_reg <= '0;
        end else if (~global_stall) begin
            id_dis_reg <= id_dis_reg_next;
        end
    end
    

    // cp1 line buffer
    logic [255:0] dfp_rdata_buf;
    logic [31:0]  dfp_addr_buf;

    // icache write signals should always be 0 
    assign icache_dfp_write = 1'b0;
    assign icache_dfp_wdata = '0;
    
    icache inst_cache(
        .clk (clk),
        .rst (rst),
        .ufp_addr(fetch_addr),
        .ufp_rmask(fetch_rmask),
        .ufp_rdata(fetch_rdata),
        .ufp_resp(fetch_resp),
        .dfp_addr(icache_dfp_addr),
        .dfp_read(icache_dfp_read),
        .dfp_rdata(icache_dfp_rdata),
        .dfp_resp(icache_dfp_resp),

        //line buffer
        .dfp_rdata_buf(dfp_rdata_buf),
        .dfp_addr_buf(dfp_addr_buf),

        .fetch(fetch),
        .flush(flush),
        .flush_pc(rvfi_rob.pc_next)
    );

    dcache dcache(
        .clk        (clk),
        .rst        (rst),
        //.flush (flush),
        // these values will come from memory when that exists 
        .ufp_addr   (lsq_dcache_addr),  
        .ufp_rmask  (lsq_dcache_rmask),
        .ufp_wmask  (lsq_dcache_wmask),
        .ufp_rdata  (lsq_dcache_rdata),    // an output from cache            
        .ufp_wdata  (lsq_dcache_wdata),
        .ufp_resp   (lsq_dcache_resp),
        .prefetch_addr (dcache_pf_addr),

        // Downward side
        .dfp_addr   (dcache_dfp_addr),   
        .dfp_read   (dcache_dfp_read),    
        .dfp_write  (dcache_dfp_write),  
        .dfp_rdata  (dcache_dfp_rdata),  
        .dfp_wdata  (dcache_dfp_wdata),   
        .dfp_resp   (dcache_dfp_resp)    

    );

    icache_adapter icache_adapter (                                                   
        .clk(clk),
        .rst(rst),
        .dfp_addr(icache_dfp_addr),
        .dfp_read(icache_dfp_read),
        .dfp_write(icache_dfp_write),
        .dfp_rdata(icache_dfp_rdata),
        .dfp_wdata(icache_dfp_wdata),
        .dfp_resp(icache_dfp_resp),

        .prefetch_valid (nlp_valid),
        .pf_rdata       (nlp_rdata),
        .pf_addr_out    (nlp_raddr),

        .cache_addr (icache_bmem_addr),
        .cache_read (icache_bmem_read),
        .cache_write(),
        .cache_wdata(),
        .cache_ready(icache_bmem_ready),
        .cache_raddr(icache_bmem_raddr),
        .cache_rdata(icache_bmem_rdata),
        .cache_rvalid(icache_bmem_rvalid)
    );

    cache_adapter dcache_adapter (                                            
        .clk(clk),
        .rst(rst),

        .dfp_addr(dcache_dfp_addr),
        .dfp_read(dcache_dfp_read),
        .dfp_write(dcache_dfp_write),
        .dfp_rdata(dcache_dfp_rdata),
        .dfp_wdata(dcache_dfp_wdata),
        .dfp_resp(dcache_dfp_resp),
        .prefetch_addr (dcache_pf_addr),

        .cache_addr (dcache_bmem_addr),
        .cache_read (dcache_bmem_read),
        .cache_write(dcache_bmem_write),
        .cache_wdata(dcache_bmem_wdata),
        .cache_ready(dcache_bmem_ready),
        .cache_raddr(dcache_bmem_raddr),
        .cache_rdata(dcache_bmem_rdata),
        .cache_rvalid(dcache_bmem_rvalid),
        
        .dcache_write(|lsq_dcache_wmask),
        .dcache_addr(lsq_dcache_addr)
    );
    
    front_arbiter arb(
        .clk                (clk),
        .rst                (rst),    
        .bmem_addr(bmem_addr),
        .bmem_read(bmem_read),
        .bmem_rdata(bmem_rdata),
        .bmem_rvalid(bmem_rvalid),
        .bmem_write(bmem_write),
        .bmem_wdata(bmem_wdata),
        .bmem_ready(bmem_ready),
        .bmem_raddr(bmem_raddr),

        // icache <- arbiter
        .icache_addr   (icache_bmem_addr),
        .icache_read   (icache_bmem_read),
        // .icache_write  (icache_bmem_write),
        // .icache_wdata  (icache_bmem_wdata),
        .icache_ready  (icache_bmem_ready),
        .icache_raddr  (icache_bmem_raddr),
        .icache_rdata  (icache_bmem_rdata),
        .icache_rvalid (icache_bmem_rvalid),

        // dcache <- arbiter
        .dcache_addr   (dcache_bmem_addr),
        .dcache_read   (dcache_bmem_read),
        .dcache_write  (dcache_bmem_write),
        .dcache_wdata  (dcache_bmem_wdata),
        .dcache_ready  (dcache_bmem_ready),
        .dcache_raddr  (dcache_bmem_raddr),
        .dcache_rdata  (dcache_bmem_rdata),
        .dcache_rvalid (dcache_bmem_rvalid)
    );

    logic br_commit_valid;
    logic [31:0] br_commit_pc, br_commit_pc_next;
    instr_t rvfi_inst;
    logic [31:0] rvfi_rd_v;
    logic rvfi_valid;
    logic [63:0] rvfi_order;

    if_stage fetch_stage(
        .clk            (clk),
        .rst            (rst),
        
        // need to implement this still 
        .flush          (flush),
        
        // Branch prediction (for future)
        // .branch_prediction (branch_prediction),
        // .branch_pc      (branch_pc),

        .fetch_addr     (fetch_addr),
        .fetch_rmask    (fetch_rmask),
        .fetch_rdata    (fetch_rdata),

        //line buffer
        .dfp_rdata_buf(dfp_rdata_buf),
        .dfp_addr_buf(dfp_addr_buf),
        .imem_valid (imem_valid),
        .global_stall(global_stall), 

        //NLP
        .pf_valid(nlp_valid),
        .pf_addr_buf(nlp_raddr),
        .pf_rdata_buf(nlp_rdata),
        
        // To decode stage
        .if_id_reg_out      (if_id_reg),
        .flush_tag(rvfi_rob.tag),
        .flush_pc(rvfi_rob.pc_next),
        .fetch(fetch),

        //branch predic training data
        .br_commit_valid(br_commit_valid),
        .br_commit_pc(rvfi_rob.pc),
        .br_commit_pc_next(rvfi_rob.pc_next),
        .jalr_valid (cdb_output.wb_valid && cdb_output.inst.j_type.opcode == op_jalr), 
        .jalr_wb_tag(cdb_output.wb_tag),
        .jalr_target(cdb_output.pc_wdata),

        .jalr_commit_valid(rvfi_valid && rvfi_rob.instruction.j_type.opcode == op_jalr),
        .jalr_commit_rd_v(rvfi_rob.store_value),
        .jalr_commit_inst(rvfi_rob.instruction)
    );


    id_stage decode(

        .if_id_reg      (if_id_reg),

        // To dispatch stage
        .id_dis_reg_next(id_dis_reg_next)
    );


    // only rename during !global stall
    // for now this is when imem_valid

    // commit and writeback logic

    logic prf_data_we;    // write data to prf when the instruction is complete (writeback, not yet at commit phase)

    logic [PRF_BITS:0]  wb_paddr; // physical address, contains data saying if it's renamed or not
    logic [31:0] wb_wdata; // data to write

    logic arf_commit;     // write data to arf on commit, also free entry in prf (long)
    logic [4:0] commit_rd;
    logic [PRF_BITS:0] commit_paddr;
    logic [31:0] commit_data;

    // keep these 0 for now 
    // these should be changed in commit/writeback logic
    assign arf_commit = rvfi_rob.ready & rvfi_rob.valid; // determined by ROB
    
    assign prf_data_we = cdb_output.wb_valid; // determined by WB / CDB

    assign wb_paddr = cdb_output.wb_physical_reg; // should be wb data from WB/CDB 
    assign wb_wdata = cdb_output.wb_value;

    assign commit_paddr = rvfi_rob.dest_physical_reg; // should be wb info from the ROB head
    assign commit_rd = rvfi_rob.rd_s;   //
    assign commit_data = rvfi_rob.store_value; // 

    prf_type_t prf_data [PRF_ENTRIES];

    logic [31:0] load_result;
    logic [1:0]  load_addr_offset;
    //logic [ROB_BITS-1:0] flush_tag;
    assign load_addr_offset =  mem_to_rob.addr_offset[1:0]; 
    always_comb begin
        load_result = mem_to_rob.mem_rdata;  
        
        if(mem_to_rob.mem_resp) begin
        unique case(mem_to_rob.inst[14:12])
            lb: load_result = {{24{mem_to_rob.mem_rdata[7 + 8*load_addr_offset]}},  mem_to_rob.mem_rdata[8*load_addr_offset +: 8]};
            lbu: load_result = {{24{1'b0}},  mem_to_rob.mem_rdata[8*load_addr_offset +: 8]};
            lh: load_result = {{16{mem_to_rob.mem_rdata[15 + 16*load_addr_offset[1]]}},  mem_to_rob.mem_rdata[16*load_addr_offset[1] +: 16]};
            lhu: load_result = {{16{1'b0}}, mem_to_rob.mem_rdata[16*load_addr_offset[1] +: 16]}; 
            lw: load_result = mem_to_rob.mem_rdata;
            default: load_result = mem_to_rob.mem_rdata;
        endcase
        end
    end

     // Dispatch 
    logic                   lsq_alloc_valid;
    logic                   lsq_alloc_is_load;
    logic                   lsq_alloc_is_store;
    logic [ROB_BITS-1:0]    lsq_alloc_rob_tag;
    // logic [63:0]            lsq_alloc_order;
    logic [31:0]            lsq_alloc_inst;
    logic [PRF_BITS:0]      lsq_alloc_dest_preg;

    // From LSQ to dispatch - backpressure
    logic                   lsq_ld_full;
    logic                   lsq_st_full;


    logic [PRF_BITS:0] rs1_paddr, rs2_paddr, rd_paddr;
    logic rs1_ready_dispatch, rs2_ready_dispatch;
    logic [31:0] rs1_v, rs2_v;

    rat_prf prf (
        .clk(clk),
        .rst(rst),
        .flush(flush),
        .global_stall(global_stall),
        .arf_commit(arf_commit),
        .prf_data_we(prf_data_we),
        .wb_paddr(wb_paddr),
        .commit_paddr(commit_paddr),
        .commit_data(commit_data),
        .wb_wdata(wb_wdata),
        .commit_rd(commit_rd),
        .rd_dispatch(id_dis_reg.rd_s),
        .rs1_dispatch(id_dis_reg.rs1_s),
        .rs2_dispatch(id_dis_reg.rs2_s),
        .rs1_ready_dispatch(rs1_ready_dispatch),
        .rs2_ready_dispatch(rs2_ready_dispatch),
        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        .rs1_paddr(rs1_paddr),
        .rs2_paddr(rs2_paddr),
        .rd_paddr(rd_paddr),
        // .cdb_output(cdb_output),
        .prf_data(prf_data)
    );


    // Dispatch 


   
    dispatch dispatch(
        .decode_in(id_dis_reg),
        .global_stall(global_stall),
        .rob_out(dispatch_to_rob),
        .mul_rs_out(dispatch_mul_rs),
        .alu_rs_out(dispatch_alu_rs),
        .mem_rs_out(dispatch_mem_rs),
        .branch_rs_out(dispatch_br_rs),
        .mul_rs_full(mul_rs_full),
        .alu_rs_full(alu_rs_full),
        .mem_rs_full(mem_rs_full),
        .br_rs_full(br_rs_full),
        .dispatch_stall(dispatch_stall),
        .rs1_paddr(rs1_paddr),
        .rs2_paddr(rs2_paddr),
        .rd_paddr(rd_paddr),
        .rs1_ready(rs1_ready_dispatch),
        .rs2_ready(rs2_ready_dispatch),
        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        .lsq_alloc_valid    (lsq_alloc_valid),
        .lsq_alloc_is_load  (lsq_alloc_is_load),
        .lsq_alloc_is_store (lsq_alloc_is_store),
        .lsq_alloc_rob_tag  (lsq_alloc_rob_tag),
        // .lsq_alloc_order    (lsq_alloc_order),
        .lsq_alloc_inst     (lsq_alloc_inst),
        .lsq_alloc_dest_preg(lsq_alloc_dest_preg),
        .lsq_ld_full        (lsq_ld_full),
        .lsq_st_full        (lsq_st_full)
       // .dispatch_valid(dispatch_valid)
    );



    rob robert_bao(
        .clk(clk),
        .rst(rst),
        .dispatch_in(dispatch_to_rob),
        .rob_full(rob_full),
        .rob_empty(rob_empty),
        .rob_top(rvfi_rob),
        .cdb_in(cdb_output),
        .flush(flush),
        .rob_to_mem(rob_to_mem),
        .mem_to_rob(mem_to_rob),

        //branch pred logic
        .br_commit_valid(br_commit_valid),
        .br_commit_pc(br_commit_pc),
        .br_commit_pc_next(br_commit_pc_next),

        .load_result(load_result)
    );

    /// Reservation stations 
        
    cdb_t alu_top, mul_top, mem_top, br_top;
    logic cdb_pop_alu, cdb_pop_mul, cdb_pop_mem, cdb_pop_br;
    logic alu_fifo_full, alu_fifo_empty; 
    logic mul_fifo_full, mul_fifo_empty;
    logic mem_fifo_full, mem_fifo_empty; 
    logic br_fifo_full, br_fifo_empty;

    reservation_station #(.ENTRIES(ALU_RS_ENTRIES)) alu_rs(
       // .alloc_en(), // we don't need this, just use dispatch_in.alloc_en
        .dispatch_in(dispatch_alu_rs),
        .clk(clk),
        .rst(rst),
        .fu_ready(!alu_fifo_full), // we need to fix this dispatch_alu_rslogic 
        // currently we only set this AFTER an inst goes through,
        // but isn't set high at the start
        .rs_out(alu_rs_output),
        .rs_full(alu_rs_full),
        .prf(prf_data),
        .cdb_in(cdb_output),
        .flush(flush)
    );

    reservation_station #(.ENTRIES(4)) multiply_divide_rs(
        .dispatch_in(dispatch_mul_rs),
        .clk(clk),
        .rst(rst),
        .fu_ready(!mul_fifo_full & !mul_stall), 
        .rs_out(mul_rs_output),
        .rs_full(mul_rs_full),
        .prf(prf_data),
        .cdb_in(cdb_output),
        .flush(flush)
    );

    reservation_station #(.ENTRIES(4)) br_rs(
        .dispatch_in(dispatch_br_rs),
        .clk(clk),
        .rst(rst),
        .fu_ready(!br_fifo_full), 
        .rs_out(br_rs_output),
        .rs_full(br_rs_full),
        .prf(prf_data),
        .cdb_in(cdb_output),
        .flush(flush)
    );

    reservation_station #(.ENTRIES(8)) memory_rs(
        .dispatch_in(dispatch_mem_rs),
        .clk(clk),
        .rst(rst),
        .fu_ready(!mem_fifo_full), 
        .rs_out(mem_rs_output),
        .rs_full(mem_rs_full),
        .prf(prf_data),
        .cdb_in(cdb_output),
        .flush(flush)
    );

    //     reservation_station multiply_divide_rs(
    //     .alloc_en(),
    //     .dispatch_in(),
    //     .clk(),
    //     .rst(),
    //     .cdb_in(),
    //     .fu_ready(),
    //     .rs_out(),
    //     .issue_valid(),
    //     .rs_full()    
    // );


    /// Issue 


    // issue iss( 
    //     // .clk (clk), 
    //     // .rst (rst),
    //     .alu_inst(alu_rs_output), // coming from alu rs 
    //     .muldi_inst(mul_rs_output), // coming from muldi rs
    //     .mem_inst(mem_rs_output), // coming from mem rs
    //     .br_inst(br_rs_output),
    //     .mult_ready(!mul_fifo_full & !mul_stall), 
    //     .alu_ready(!alu_fifo_full), // don't implement alu stall bc data is always ready in 1 cycle!
    //     .memory_ready(!mem_fifo_full), 
    //     .branch_ready(!br_fifo_full), 
    //     .can_begin_alu(can_begin_alu), 
    //     .can_begin_mult(can_begin_mult),
    //     .can_begin_mem(can_begin_mem),
    //     .can_begin_br(can_begin_br)
    // );

    /// Functional units 

    alu_func_unit alu( // yeah this is the whole interface lol
        .rs_entry (alu_rs_output),
        .fu_result(alu_out)
    );

    logic mul_op_done;
    logic mem_op_done;
    mult_func_unit muldiv(
        .clk(clk),
        .rst(rst),
        .rs_entry_mult(mul_rs_output),
        .can_begin('1),
        .fu_result_mult(mul_div_out),
        .mul_stall(mul_stall),
        .op_done(mul_op_done),
        .flush(flush)
    );

    mem_func_unit split_lsq(
        .clk(clk),
        .rst(rst),
        
        .flush(flush),
        .rs_entry_mem(mem_rs_output),
        .fu_result_mem(mem_out),
        .rob_head_tag(rvfi_rob.tag),
        .dcache_addr(lsq_dcache_addr),
        .dcache_wdata(lsq_dcache_wdata),
        .dcache_wmask(lsq_dcache_wmask),
        .dcache_rmask(lsq_dcache_rmask),
        .dcache_rdata(lsq_dcache_rdata),
        .dcache_resp(lsq_dcache_resp),
        .lsq_full(lsq_full),
        .mem_to_rob(mem_to_rob),
        // .mem_fu_buffer_full(mem_fifo_full),
        // .cdb_output(cdb_output),
        .lsq_alloc_valid    (lsq_alloc_valid),
        .lsq_alloc_is_load  (lsq_alloc_is_load),
        .lsq_alloc_is_store (lsq_alloc_is_store),
        .lsq_alloc_rob_tag  (lsq_alloc_rob_tag),
        // .lsq_alloc_order    (lsq_alloc_order),
        .lsq_alloc_inst     (lsq_alloc_inst),
        .lsq_alloc_dest_preg(lsq_alloc_dest_preg),
        .lsq_ld_full        (lsq_ld_full),
        .lsq_st_full        (lsq_st_full),
        .commit_tag         (rvfi_rob.tag)
        //.flush_tag(flush_tag)
    );


    br_func_unit br(
        .rs_entry(br_rs_output),
        .fu_result(br_out)
    );

    //***********************BEGIN ARBITER LOGIC ***********************//
//   choose which entry to send to cdb 


    fifo #(.T(cdb_t), .ENTRIES(BUFFER_SIZE)) alu_fu_buffer (
        .clk        (clk),
        .rst        (rst),
        .data_in    (alu_out),
        .push       (alu_out.wb_valid),
        .data_out   (alu_top),
        .pop        (cdb_pop_alu),
        .queue_full (alu_fifo_full),
        .queue_empty(alu_fifo_empty),
        .clear(flush)
    );
    
    fifo #(.T(cdb_t), .ENTRIES(BUFFER_SIZE)) mul_fu_buffer(
        .clk(clk),
        .rst(rst),
        .data_in(mul_div_out),
        .push(mul_div_out.wb_valid),
        .data_out(mul_top), 
        .pop(cdb_pop_mul),
        .queue_full(mul_fifo_full),
        .queue_empty(mul_fifo_empty),
        .clear(flush)
    ); 

    fifo #(.T(cdb_t), .ENTRIES(BUFFER_SIZE)) br_fu_buffer(
        .clk(clk),
        .rst(rst),
        .data_in(br_out),
        .push(br_out.wb_valid),
        .data_out(br_top), 
        .pop(cdb_pop_br),
        .queue_full(br_fifo_full),
        .queue_empty(br_fifo_empty),
        .clear(flush)
    ); 

    fifo #(.T(cdb_t), .ENTRIES(BUFFER_SIZE)) mem_fu_buffer(
        .clk(clk),
        .rst(rst),
        .data_in(mem_out),
        .push(mem_out.wb_valid),
        .data_out(mem_top), 
        .pop(cdb_pop_mem),
        .queue_full(mem_fifo_full),
        .queue_empty(mem_fifo_empty),
        .clear(flush)
    ); 

    // Arbiter: pick the oldest (smallest .order) among available FU outputs.
    

    // logic [63:0] min_order;
    logic rob_mem, rob_alu, rob_mul, rob_br;
    always_comb begin
        // determine rob top type -- I commented this out because it was our critical path
        rob_mem = '0;
        rob_alu = '0;
        rob_mul = '0;
        rob_br = '0;
        unique case(rvfi_rob.instruction.r_type.opcode) 
            op_imm, op_lui, op_auipc: rob_alu = '1;
            op_load, op_store: rob_mem = '1;
            op_br, op_jal, op_jalr: rob_br = '1;
            op_reg: begin
                if (rvfi_rob.instruction.r_type.funct7[0]) rob_mul ='1;
                else rob_alu = '1;
            end
            default: rob_alu = '0;// do nothing
        endcase

        cdb_pop_alu = '0;
        cdb_pop_br = '0;
        cdb_pop_mul = '0;
        cdb_pop_mem = '0;
        cdb_output = '0;
        if (~br_fifo_empty & rob_br) begin
            cdb_pop_br = '1;
            cdb_output = br_top;
        end else if (~alu_fifo_empty & rob_alu) begin
            cdb_pop_alu = '1;
            cdb_output = alu_top;
        end else if (~mul_fifo_empty & rob_mul) begin
            cdb_pop_mul = '1;
            cdb_output = mul_top;
        end else if (~mem_fifo_empty & rob_mem) begin
            cdb_pop_mem = '1;
            cdb_output =    mem_top;
        end else 
        if (~br_fifo_empty) begin
            cdb_pop_br = '1;
            cdb_output = br_top;
        end else if (~alu_fifo_empty) begin
            cdb_pop_alu = '1;
            cdb_output = alu_top;
        end else if (~mul_fifo_empty) begin
            cdb_pop_mul = '1;
            cdb_output = mul_top;
        end else if (~mem_fifo_empty) begin
            cdb_pop_mem = '1;
            cdb_output = mem_top;
        end
    end

    //***********************END ARBITER LOGIC ***********************//

    // monitor signals -- we should keep this modular so we don't need to edit the json

    logic [4:0]  rvfi_rs1_s, rvfi_rs2_s, rvfi_rd_s;
    logic [31:0] rvfi_rs1_v, rvfi_rs2_v;
    logic [31:0] rvfi_pc, rvfi_pc_next;
    logic [31:0] rvfi_mem_addr, rvfi_mem_rdata, rvfi_mem_wdata;
    logic [3:0]  rvfi_mem_wmask, rvfi_mem_rmask;

    //rvfi_order: 
    always_ff @ (posedge clk) begin
        if (rst) rvfi_order <= '0;
        else if (rvfi_valid) rvfi_order <= rvfi_order + 1'b1;
    end

    assign rvfi_valid = rvfi_rob.ready & rvfi_rob.valid; // since it's ooo it should not depend on global stalls
    // keep the & valid because sometimes ready is high when everything else is 0?
    assign rvfi_inst  = rvfi_rob.instruction;
    assign rvfi_rs1_s = rvfi_rob.rs1_s;
    assign rvfi_rs2_s = rvfi_rob.rs2_s;
    assign rvfi_rd_s  = rvfi_rob.rd_s;
    assign rvfi_rs1_v = rvfi_rob.rs1_v;
    assign rvfi_rs2_v = rvfi_rob.rs2_v;
    assign rvfi_rd_v  = rvfi_rob.store_value;
    assign rvfi_pc    = rvfi_rob.pc;
    assign rvfi_pc_next = rvfi_rob.pc_next;
    assign rvfi_mem_addr = rvfi_rob.mem_addr;
    assign rvfi_mem_rdata = rvfi_rob.mem_rdata;
    assign rvfi_mem_wdata = rvfi_rob.mem_wdata;
    assign rvfi_mem_wmask = rvfi_rob.mem_wmask;
    assign rvfi_mem_rmask = rvfi_rob.mem_rmask;


endmodule : cpu