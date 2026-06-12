`include "fsm.v"
`include "cache_mem.v"
`include "hit_detector.v"
`include "lru.v"

// Instantiates and connects:
// -cache_mem: the 4-way storage array
// -hit_detector: tag comparator, produces hit + hit_way
// -fsm: controls state transitions and signals
// -lru: age-counter based LRU victim selector
//
// Address breakdown (32-bit):
// [31:13]= TAG(19 bits)
// [12:6]= INDEX(7 bits)
// [5:0]= OFFSET(6 bits)
//
// Write policy : write-back + write-allocate
// Replacement  : LRU

module cache_controller (
    input clk,
    input rst_b,

   
    input [31:0] addr,       
    input op_read,    
    input op_write,   
    input [511:0] cpu_data_in, 

    // Memory interface
    input [511:0] mem_data_in, // block fetched from main memory (on read miss)

    // Outputs to CPU
    output [511:0] data_out,  // block returned to CPU on read hit
    output ready,     // 1 = operation complete this cycle

    // Outputs to memory controller
    output mem_read,  // 1 = fetch block from main memory
    output mem_write, // 1 = write block back to main memory
    output [31:0] mem_addr,  // address for memory operation
    output [511:0] evict_data // dirty block to write back on eviction
);


wire [18:0] addr_tag = addr[31:13];
wire [6:0] addr_index = addr[12:6];
// addr[5:0] is the byte offset - used outside this module

// Internal wires between modules


// cache_mem outputs
wire [18:0] tag0, tag1, tag2, tag3;
wire valid0, valid1, valid2, valid3;
wire dirty0, dirty1, dirty2, dirty3;
wire [511:0] data0, data1, data2, data3;

// hit_detector outputs
wire hit;
wire [1:0]  hit_way;

// fsm outputs
wire [2:0] current_state;
wire try_read, try_write;
wire cache_write;
// mem_read, mem_write, ready are direct outputs

// lru output
wire [1:0] lru_way;


wire [1:0] write_way = hit ? hit_way : lru_way;


reg req_write;
reg [511:0] req_wdata;

reg dirty_lru;
always @(*) begin
    case (lru_way)
        2'd0: dirty_lru = dirty0;
        2'd1: dirty_lru = dirty1;
        2'd2: dirty_lru = dirty2;
        2'd3: dirty_lru = dirty3;
    endcase
end


wire [511:0] cache_data_in = req_write ? req_wdata : mem_data_in;

wire valid_in = 1'b1;
wire dirty_in = req_write;
always @(posedge clk or negedge rst_b)
begin
    if(!rst_b)
    begin
        req_write <= 1'b0;
        req_wdata <= 512'b0;
    end
    else if(current_state == 3'b000 &&    //IDLE
            (op_read || op_write))
    begin
        req_write <= op_write;
        req_wdata <= cpu_data_in;
    end
end

reg [511:0] evict_data_reg;
always @(*) begin
    case (lru_way)
        2'd0: evict_data_reg = data0;
        2'd1: evict_data_reg = data1;
        2'd2: evict_data_reg = data2;
        2'd3: evict_data_reg = data3;
    endcase
end
assign evict_data = evict_data_reg;

reg [18:0] evict_tag;
always @(*) begin
    case (lru_way)
        2'd0: evict_tag = tag0;
        2'd1: evict_tag = tag1;
        2'd2: evict_tag = tag2;
        2'd3: evict_tag = tag3;
    endcase
end

assign mem_addr = mem_write ? {evict_tag, addr_index, 6'b0} : {addr_tag,  addr_index, 6'b0};


reg [511:0] data_out_reg;


always @(*) begin
    case (write_way)
        2'd0: data_out_reg = data0;
        2'd1: data_out_reg = data1;
        2'd2: data_out_reg = data2;
        2'd3: data_out_reg = data3;
    endcase
end
assign data_out = data_out_reg;

wire lru_update_en = cache_write;
wire [1:0] lru_update_way = hit ? hit_way : lru_way;

// Module instantiations

cache_mem u_cache_mem (
    .clk(clk),
    .rst_b(rst_b),
    .index(addr_index),
    .write_en(cache_write),
    .write_way(write_way),
    .tag_in(addr_tag),
    .data_in(cache_data_in),
    .valid_in(valid_in),
    .dirty_in(dirty_in),
    .tag0(tag0), .tag1(tag1), .tag2(tag2), .tag3(tag3),
    .valid0 (valid0), .valid1(valid1), .valid2(valid2), .valid3(valid3),
    .dirty0(dirty0), .dirty1(dirty1), .dirty2(dirty2), .dirty3(dirty3),
    .data0(data0), .data1(data1), .data2(data2), .data3(data3)
);

hit_detector u_hit_detector (
    .addr_tag(addr_tag),
    .tag0(tag0), .tag1(tag1), .tag2(tag2), .tag3(tag3),
    .valid0(valid0), .valid1(valid1), .valid2(valid2), .valid3(valid3),
    .hit(hit),
    .hit_way(hit_way)
);

fsm u_fsm (
    .clk(clk),
    .rst_b(rst_b),
    .hit(hit),
    .dirty(dirty_lru),
    .op_read(op_read),
    .op_write(op_write),
    .current_state(current_state),
    .try_read(try_read),
    .try_write(try_write),
    .mem_read(mem_read),
    .mem_write(mem_write),
    .cache_write(cache_write),
    .ready(ready)
);

lru u_lru (
    .clk(clk),
    .rst_b(rst_b),
    .index(addr_index),
    .update_en(lru_update_en),
    .update_way(lru_update_way),
    .lru_way(lru_way)
);

endmodule
