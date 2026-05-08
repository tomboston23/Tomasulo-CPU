package cache_types;

  localparam ROB_ENTRIES = 16;
  localparam ALU_RS_ENTRIES = 4;
  localparam RS_ENTRIES = 4;
  localparam PRF_ENTRIES = ROB_ENTRIES;
  localparam BUFFER_SIZE = 4;
  localparam PRF_BITS = $clog2(PRF_ENTRIES);
  localparam ROB_BITS = $clog2(ROB_ENTRIES);

  typedef enum logic [6:0] {
    op_lui       = 7'b0110111, // load upper imemediate (U type)
    op_auipc     = 7'b0010111, // add upper imemediate PC (U type)
    op_jal       = 7'b1101111, // jump and link (J type)
    op_jalr      = 7'b1100111, // jump and link register (I type)
    op_br        = 7'b1100011, // branch (B type)
    op_load      = 7'b0000011, // load (I type)
    op_store     = 7'b0100011, // store (S type)
    op_imm       = 7'b0010011, // arith ops with register/imemediate operands (I type)
    op_reg       = 7'b0110011  // arith ops with register operands (R type)
  } rv32i_opcode;

  typedef enum logic [2:0] {
    beq  = 3'b000,
    bne  = 3'b001,
    blt  = 3'b100,
    bge  = 3'b101,
    bltu = 3'b110,
    bgeu = 3'b111
  } branch_funct3_t;

  typedef enum logic [2:0] {
    lb  = 3'b000,
    lh  = 3'b001,
    lw  = 3'b010,
    lbu = 3'b100,
    lhu = 3'b101
  } load_funct3_t;

  typedef enum logic [2:0] {
    sb = 3'b000,
    sh = 3'b001,
    sw = 3'b010
  } store_funct3_t;

  typedef enum logic [2:0] {
    add  = 3'b000, //check logic 30 for sub if op_reg opcode
    sll  = 3'b001,
    slt  = 3'b010,
    sltu = 3'b011,
    axor = 3'b100,
    sr   = 3'b101, //check logic 30 for logical/arithmetic
    aor  = 3'b110,
    aand = 3'b111
  } arith_funct3_t;

  typedef enum logic [2:0] {
    mul    = 3'b000, // S x S lower 32
    mulh   = 3'b001, // S x S upper 32
    mulhsu = 3'b010, // S x U upper 32
    mulhu  = 3'b011, // U x U upper 32
    div    = 3'b100, // S / S, round down
    divu   = 3'b101, // U / U, round down
    rem    = 3'b110, // S % S 
    remu   = 3'b111  // U % U
  } mul_div_func3_t;

  typedef enum logic [2:0] {
    alu_add = 3'b000,
    alu_sll = 3'b001,
    alu_sra = 3'b010,
    alu_sub = 3'b011,
    alu_xor = 3'b100,
    alu_srl = 3'b101,
    alu_or  = 3'b110,
    alu_and = 3'b111
  } alu_ops;

  typedef union packed {
    logic [31:0] word;

    struct packed {
      logic [11:0] i_imm;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  rd;
      rv32i_opcode opcode;
    } i_type;

    struct packed {
      logic [6:0]  funct7;
      logic [4:0]  rs2;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  rd;
      rv32i_opcode opcode;
    } r_type;

    struct packed {
      logic [31:12] j_imm;
      logic [4:0]   rd;
      rv32i_opcode  opcode;
    } j_type;

    struct packed {
      logic [31:12] u_imm;
      logic [4:0]   rd;
      rv32i_opcode opcode;
    } u_type;

    // s type and b type have non-contiguous imm so I deleted them
    // you can get rs1 rs2 and rd from other types

  } instr_t;

  typedef enum logic [1:0] {
    idle  = 2'd0, 
    hit   = 2'd1, 
    wb    = 2'd2,  
    alloc = 2'd3   
  } cache_state_t;

  typedef struct packed {
    logic [31:0] addr;     
    logic [3:0]  r_mask;  
    logic [3:0]  w_mask;   
    logic [31:0] w_data;   
  } cpu_input_t;

  typedef struct packed {
    logic [31:0] addr;
    logic read;
  } imem_input_t;

  typedef struct packed {
    logic [31:0]  addr;     
    logic         read;    
    logic         write;   
    logic [255:0] w_data;   
  } mem_input_t;

  typedef struct packed {
    logic in_use;// how do we determine if we still need it?
    logic valid; // data is ready
    logic [31:0] data;
  } prf_type_t;

  typedef struct packed {
    logic renamed;
    logic [PRF_BITS-1:0] addr; // address to register file or PRF - only needs to be 6 bits
  } rat_type_t;

  typedef struct packed {
    logic        valid;      
    logic [31:0] pc;        
    logic [31:0] pc_next;    
    instr_t inst;       
    // logic [63:0] order;      
    logic [ROB_BITS-1:0] tag;
  } if_id_reg_t;

  typedef struct packed {
    logic        valid;      
    logic [31:0] pc;        
    logic [31:0] pc_next;    
    instr_t inst;       
    // logic [63:0] order;      
    logic [ROB_BITS-1:0] tag;
    logic [4:0] rs1_s, rs2_s, rd_s;
  } id_dis_reg_t;

  
  typedef struct packed {
    logic                            valid;        // entry in use
    instr_t                          inst;  
    logic [31:0]                     src1_value;   // operand 1 value (if ready)
    logic                            src1_ready;   // 1 if src1_value is valid
    logic [PRF_BITS:0]  src1_physical_reg;// physical register that this source is waiting for
    logic [31:0]                     src2_value;   // operand 2 value (if ready)
    logic                            src2_ready;   // 1 if src2_value is valid
    logic [PRF_BITS:0]  src2_physical_reg;// physical register that this source is waiting for
    logic [$clog2(ROB_ENTRIES)-1:0]  dest_tag;     // where result will be written in ROB
    logic  [PRF_BITS:0]   dest_physical_reg;  //the destination register's physical register address
    logic is_store, is_load;
   // logic [63:0] order;
    logic [31:0] pc;
  } rs_entry_t;



  typedef struct packed{
    logic wb_valid; //is high when CDB is broadcasting a result
    logic [$clog2(ROB_ENTRIES)-1:0] wb_tag; //rob tag of the producer
    logic [31:0] rs1_v, rs2_v, wb_value; //produced value from FU
    // need rs1_v and rs2_v for rvfi !
    logic [PRF_BITS:0] wb_physical_reg;
    instr_t inst ; 
   // logic [63:0] order;
    logic [31:0] mem_addr, mem_wdata;
    logic [3:0] mem_wmask;
    logic [3:0] mem_rmask;
    logic [31:0] pc_wdata;
    logic is_a_load ; 
    // logic [31:0] misaligned_mem_addr;
    logic [1:0] addr_offset; //just needs offset
    logic [31:0] mem_rdata;
  } cdb_t;


  typedef struct packed {
    logic valid; //is entry in use?
    logic ready; //has instructoin completed execution?
    instr_t instruction; //make this a struct so it holds a ton of data
    logic [4:0] rd_s; //destination register (architectural)
    logic is_store, is_load; 
    logic [$clog2(ROB_ENTRIES)-1:0] tag; //rob index
    logic [31:0] store_value;
    logic [PRF_BITS:0] dest_physical_reg;


    //rvfi signals
    logic [4:0] rs1_s, rs2_s;
    logic [31:0] rs1_v, rs2_v;
    // logic [63:0] order;
    logic [31:0] mem_addr;
    logic [31:0] mem_rdata; 
    logic [31:0] mem_wdata;
    logic [3:0] mem_wmask;
    logic [3:0] mem_rmask;
    logic [31:0] pc, pc_pred, pc_next;
    // mem rvfi signal can be added later
    logic i_talked_to_cdb;
    // logic [31:0] misaligned_mem_addr;
    logic [1:0] addr_offset;
  } rob_entry_t;


typedef struct packed {
  logic valid;
  logic [31:0] mem_addr, mem_wdata;
  logic [3:0] mem_wmask, mem_rmask;
} rob_to_mem_t;

typedef struct packed {
  logic mem_resp;
  logic [31:0] mem_rdata;
  logic is_store;
  logic [31:0] load_data;
  logic [3:0] mem_rmask;
  logic [3:0] mem_wmask;
  logic [31:0] mem_wdata;
  logic [31:0] mem_addr;
  logic [ROB_BITS-1:0] rob_tag;
  logic is_load;
  //logic [63:0] order;
  logic [31:0] rs1_v;
  logic [31:0] rs2_v;
  logic valid;
  logic [1:0] addr_offset;
  logic [31:0] inst;
} mem_to_rob_t;
 
// branch pred logic
localparam BHT_ENTRIES = 32; // you can change this however you want now
localparam BHT_IDX_BITS = $clog2(BHT_ENTRIES);
localparam BHT_TAG_BITS = 32-(2+BHT_IDX_BITS);
localparam PHT_ENTRIES = 32;
localparam PHT_IDX_BITS = $clog2(PHT_ENTRIES);
localparam GHT_BITS = PHT_IDX_BITS;

typedef struct packed {
  logic valid;
  logic [BHT_TAG_BITS-1:0] tag;
  logic [31:0] target;
  logic is_branch;
} bht_entry_t;

typedef struct packed {
    logic               valid;
    logic [ROB_BITS-1:0] rob_tag;
    logic [31:0]        addr;           // Word-aligned address
    logic [1:0]        addr_offset; // Original effective address
    logic               addr_ready;
    logic [31:0]        rs1_v;
    logic [31:0]        rs2_v;
    logic [3:0]         rmask;
    instr_t        inst;
    logic [PRF_BITS:0]  dest_preg;
    // logic [63:0]        age;            // Program order
    logic               issued;         // Sent to memory
} lq_entry_t;

    
typedef struct packed {
    logic               valid;
    logic [ROB_BITS-1:0] rob_tag;
    logic [31:0]        addr;           // Word-aligned address
    logic [1:0]        addr_offset; // Original effective address
    // logic               addr_ready;
    logic [31:0]        data;           // Store data (shifted)
    logic               data_ready;     // Data available
    logic               committed;      // ROB has committed this store
    logic [31:0]        rs1_v;
    logic [31:0]        rs2_v;
    logic [3:0]         wmask;
    instr_t        inst;
    logic [PRF_BITS:0]  dest_preg;
    // logic [63:0]        age;
    logic               issued;         // Sent to memory
    logic               cdb_sent;       // CDB broadcast done
} sq_entry_t;

  typedef struct packed {
    logic [31:0] rdata;     
    logic        response;  
  } cpu_output_t;


  typedef struct packed {
    logic [255:0] r_data;   
    logic         response; 
  } mem_output_t;
  
endpackage : cache_types