module rat_prf
import cache_types::*;
(
    input logic clk, rst, flush, global_stall,
    input logic arf_commit, prf_data_we, 
    input logic [PRF_BITS:0] wb_paddr, commit_paddr, 
    input logic [31:0] commit_data, wb_wdata, 
    input logic [4:0] commit_rd, rd_dispatch, rs1_dispatch, rs2_dispatch,
    output logic rs1_ready_dispatch, rs2_ready_dispatch,
    output logic [31:0] rs1_v, rs2_v,
    output logic [PRF_BITS:0] rs1_paddr, rs2_paddr,
    input  logic [PRF_BITS:0] rd_paddr,
    // input cdb_t cdb_output,
    output prf_type_t prf_data [PRF_ENTRIES]
); 
   
    rat_type_t rat_data[32];

    logic rename;
    //logic lint_rename;
    //assign lint_rename =load_wb_valid && (|load_wb_paddr) && (|load_wb_data); //suppress unused signal warning
    assign rename = rd_paddr[PRF_BITS] & ~global_stall & ~flush;


    logic push;
    assign push = arf_commit & (|commit_rd) & (commit_paddr[PRF_BITS]);

    regfile regfile(
        .clk(clk),
        .rst(rst),
        .regf_we(push),
        .rd_v(commit_data),
        .rs1_s(rs1_dispatch),
        .rs2_s(rs2_dispatch),
        .rs1_v(rs1_v),
        .rs2_v(rs2_v),
        .rd_s(commit_rd)
    );

    // deal with updates to rat and prf
    // this includes 
    // - renaming / removing from free list
    // - write back, write data to prf
    // - commit, write data to arf and add to free list
    always_ff @(posedge clk) begin
        if (rst | flush) begin
            for (integer i = 0; i < PRF_ENTRIES; i++) begin
                prf_data[i].in_use <= '0;
                prf_data[i].valid <= '0;
            end
            for (integer i = 0; i < 32; i++) begin
                rat_data[i] <= '0;
                rat_data[i].addr <= '0;
            end
        end else begin 
            if (rename) begin // rename current rd in dispatch to a prf entry
                // set corresponding flags in ratlogic push;
                rat_data[rd_dispatch].renamed <= '1;
                rat_data[rd_dispatch].addr    <= rd_paddr[PRF_BITS-1:0];
                // don't touch data here

                //set flags in prf
                prf_data[rd_paddr[PRF_BITS-1:0]].in_use <= '1;
                prf_data[rd_paddr[PRF_BITS-1:0]].valid <= '0;
            end
        end

        if (push) begin 
            // only on commit (after writeback), put data into arf and clear related prf entry
            // check we aren't writing to x0

            if(commit_paddr[PRF_BITS-1:0] == rat_data[commit_rd].addr && ~(rename && (commit_rd == rd_dispatch))) begin // relieve reg renaming flags
                rat_data[commit_rd].renamed <= '0;
            end
        end 

        if (prf_data_we ) begin 
            // this occurs on writeback; write data to prf and set flag to valid.
            // this signals to instructions in the rs that the data is ready
            if (wb_paddr[PRF_BITS]) begin // this is our renamed flag
                prf_data[wb_paddr[PRF_BITS-1:0]].data <= wb_wdata; //write data, set valid b*t high
                prf_data[wb_paddr[PRF_BITS-1:0]].valid <= '1;
            end
        end
        // doing direct loads from rob 
        //  if (load_wb_valid) begin
        //     if (load_wb_paddr[PRF_BITS]) begin  // Only if renamed
        //         prf_data[load_wb_paddr[PRF_BITS-1:0]].data <= load_wb_data;
        //         prf_data[load_wb_paddr[PRF_BITS-1:0]].valid <= 1'b1;
        //     end
        // end
    end

    // for dispatch / rename stage
    // send rs1/rs2 physical address names to dispatch
    // Get rs1_v and rs2_v IF they are not renamed
    // set ready high if not renamed
    always_comb begin
        rs1_ready_dispatch = '1; // default ready to high, change if renamed
        rs2_ready_dispatch = '1;
        if (rs1_dispatch == 0) begin // no rs1, so set to 0. keep ready flag high and data = 0
            rs1_paddr = '0;
        end else if (~rat_data[rs1_dispatch].renamed) begin // rs1 not renamed, get value from arf
            rs1_paddr = '0;
        end else begin                                    // renamed, set to not ready
            rs1_paddr = {1'b1, rat_data[rs1_dispatch].addr};
            rs1_ready_dispatch = '0;
        end 

        if (rs2_dispatch == 0) begin // no rs2, set paddr to 0 (not renamed)
            rs2_paddr = '0;
        end else if (~rat_data[rs2_dispatch].renamed) begin // not renamed, so get value straight from arf
            rs2_paddr = '0;
        end else begin                                          //renamed, set ready to 0
            rs2_paddr = {1'b1, rat_data[rs2_dispatch].addr}; 
            rs2_ready_dispatch = '0;
        end
    end


endmodule : rat_prf