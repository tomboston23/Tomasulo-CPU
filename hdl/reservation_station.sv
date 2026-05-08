
// //////// made rs_out combinational down here ////////////////////////////////////

module reservation_station
import cache_types::*;
#(
  parameter ENTRIES = 8
)
(
    input  rs_entry_t         dispatch_in,
    input  logic              clk,
    input  logic              rst,
    input  logic              fu_ready,

    output rs_entry_t         rs_out,
    output logic              rs_valid,
    output logic              rs_full,

    input  prf_type_t         prf[PRF_ENTRIES],
    input  cdb_t              cdb_in,
    input  logic              flush
);
    typedef logic [$clog2(ENTRIES)-1:0] rs_idx_t;
    rs_entry_t reservation_station_arr[ENTRIES];


    logic has_free;
    logic [$clog2(ENTRIES)-1:0] free_idx;


    always_comb begin
        has_free = '0;
        free_idx = '0;
        for (integer unsigned i = 0; i < ENTRIES; i++) begin
            if (!reservation_station_arr[i].valid) begin
                has_free = 1'b1;
                free_idx = rs_idx_t'(i);
                break;
            end
        end
    end



    logic [ENTRIES-1:0] src1_ready_now, src2_ready_now, entry_ready_now;

    always_comb begin
        for (integer i = 0; i < ENTRIES; i++) begin

            src1_ready_now[i] =
                reservation_station_arr[i].src1_ready                                   ||
                (cdb_in.wb_valid &&
                 cdb_in.wb_physical_reg == reservation_station_arr[i].src1_physical_reg) ||
                (reservation_station_arr[i].src1_physical_reg[PRF_BITS] &&
                 prf[reservation_station_arr[i].src1_physical_reg[PRF_BITS-1:0]].valid);

            src2_ready_now[i] =
                reservation_station_arr[i].src2_ready                                   ||
                (cdb_in.wb_valid &&
                 cdb_in.wb_physical_reg == reservation_station_arr[i].src2_physical_reg) ||
                (reservation_station_arr[i].src2_physical_reg[PRF_BITS] &&
                 prf[reservation_station_arr[i].src2_physical_reg[PRF_BITS-1:0]].valid);

            entry_ready_now[i] =
                reservation_station_arr[i].valid &&
                src1_ready_now[i] &&
                src2_ready_now[i];
        end
    end

    // ============================================================
    // Select first ready entry (oldest-first)
    // ============================================================
    logic some_ready_exists;
    logic [$clog2(ENTRIES)-1:0] ready_idx;
    always_comb begin
        some_ready_exists = '0;
        ready_idx = '0;
        for (integer unsigned i = '0; i < ENTRIES; i++) begin
            if (entry_ready_now[i]) begin
                some_ready_exists = 1'b1;
                ready_idx = rs_idx_t'(i);
                break;
            end
        end
    end

    // RS full: no space AND cannot free due to issue
    assign rs_full =
        !(has_free || (fu_ready && some_ready_exists));

    rs_entry_t comb_out;
    logic      comb_valid;

    always_comb begin
        comb_valid = '0;
        comb_out   = '0;

        if (fu_ready && some_ready_exists) begin
            comb_valid = 1'b1;
            comb_out   = reservation_station_arr[ready_idx];

            if (!comb_out.src1_ready) begin
                if (cdb_in.wb_valid &&
                    cdb_in.wb_physical_reg == comb_out.src1_physical_reg) begin
                    comb_out.src1_value = cdb_in.wb_value;
                    comb_out.src1_ready = 1'b1;
                end else if (comb_out.src1_physical_reg[PRF_BITS] &&
                             prf[comb_out.src1_physical_reg[PRF_BITS-1:0]].valid) begin
                    comb_out.src1_value =
                        prf[comb_out.src1_physical_reg[PRF_BITS-1:0]].data;
                    comb_out.src1_ready = 1'b1;
                end
            end


            if (!comb_out.src2_ready) begin
                if (cdb_in.wb_valid &&
                    cdb_in.wb_physical_reg == comb_out.src2_physical_reg) begin
                    comb_out.src2_value = cdb_in.wb_value;
                    comb_out.src2_ready = 1'b1;
                end else if (comb_out.src2_physical_reg[PRF_BITS] &&
                             prf[comb_out.src2_physical_reg[PRF_BITS-1:0]].valid) begin
                    comb_out.src2_value =
                        prf[comb_out.src2_physical_reg[PRF_BITS-1:0]].data;
                    comb_out.src2_ready = 1'b1;
                end
            end
        end
    end

    assign rs_out   = comb_out;
    assign rs_valid = comb_valid;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            for (integer i = 0; i < ENTRIES; i++) begin
                reservation_station_arr[i].valid <= 1'b0;
            end
        end else begin

           
            for (integer i = 0; i < ENTRIES; i++) begin
                if (reservation_station_arr[i].valid &&
                    !reservation_station_arr[i].src1_ready) begin

                    if (cdb_in.wb_valid &&
                        cdb_in.wb_physical_reg == 
                        reservation_station_arr[i].src1_physical_reg) begin
                        reservation_station_arr[i].src1_value <= cdb_in.wb_value;
                        reservation_station_arr[i].src1_ready <= 1'b1;
                    end else if (reservation_station_arr[i].src1_physical_reg[PRF_BITS] &&
                                 prf[reservation_station_arr[i].src1_physical_reg[PRF_BITS-1:0]].valid) begin
                        reservation_station_arr[i].src1_value <=
                            prf[reservation_station_arr[i].src1_physical_reg[PRF_BITS-1:0]].data;
                        reservation_station_arr[i].src1_ready <= 1'b1;
                    end
                end

                if (reservation_station_arr[i].valid &&
                    !reservation_station_arr[i].src2_ready) begin

                    if (cdb_in.wb_valid &&
                        cdb_in.wb_physical_reg == 
                        reservation_station_arr[i].src2_physical_reg) begin
                        reservation_station_arr[i].src2_value <= cdb_in.wb_value;
                        reservation_station_arr[i].src2_ready <= 1'b1;
                    end else if (reservation_station_arr[i].src2_physical_reg[PRF_BITS] &&
                                 prf[reservation_station_arr[i].src2_physical_reg[PRF_BITS-1:0]].valid) begin
                        reservation_station_arr[i].src2_value <=
                            prf[reservation_station_arr[i].src2_physical_reg[PRF_BITS-1:0]].data;
                        reservation_station_arr[i].src2_ready <= 1'b1;
                    end
                end
            end


            if (rs_valid && fu_ready) begin
                reservation_station_arr[ready_idx].valid <= 1'b0;
            end

            if (dispatch_in.valid &&
                (has_free || (rs_valid && fu_ready))) begin

                logic [$clog2(ENTRIES)-1:0] wr_idx;
                wr_idx = has_free ? free_idx : ready_idx;

                reservation_station_arr[wr_idx] <= dispatch_in;
            end
        end
    end

endmodule