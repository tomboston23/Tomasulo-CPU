module regfile
(
  input logic         clk,
  input logic         rst,
  input logic         regf_we,
  input logic [31:0]  rd_v,
  input logic [4:0]   rs1_s, rs2_s, rd_s,
  output logic [31:0] rs1_v, rs2_v
);
  logic   [31:0]  data [32];

  always_ff @(posedge clk) begin
      if (rst) begin
          data <= '{default: '0};
      end else if (regf_we && (rd_s != 5'd0)) begin
          data[rd_s] <= rd_v;
      end
  end

  always_comb begin
      if (rst) begin
          rs1_v = 'x;
      end

      // Add transparency/forwarding logic here
      else begin
          if (rs1_s == 0) begin
            rs1_v = '0;
          end else if (rd_s == rs1_s && regf_we) begin
            rs1_v = rd_v;
          end else begin
            rs1_v = data[rs1_s];
          end
      end

      if (rst) begin
          rs2_v = 'x;
      end

      // Add transparency/forwarding logic here
      
      else begin
          if (rs2_s == 0) begin
            rs2_v = '0;
          end else if (rd_s == rs2_s && regf_we) begin
            rs2_v = rd_v;
          end else begin
            rs2_v = data[rs2_s];
          end
      end
  end
endmodule : regfile
