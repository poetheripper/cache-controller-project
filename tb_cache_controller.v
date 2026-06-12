`timescale 1ns/1ps

// Tests covered:
// 1. reset
// 2. read miss  (cold cache, clean allocate)
// 3. read hit   (same address again)
// 4. write hit  (write to address already in cache)
// 5. write miss (cold address, write-allocate)
// 6. read miss  with dirty eviction (EVICT -> ALLOCATE)
// 7. LRU eviction order across 4 ways

module tb_cache_controller;

reg clk;
reg rst_b;

reg [31:0] addr;
reg op_read;
reg op_write;
reg [511:0] cpu_data_in;
reg [511:0] mem_data_in;

wire [511:0] data_out;
wire ready;
wire mem_read;
wire mem_write;
wire [31:0] mem_addr;
wire [511:0] evict_data;

// module instantiations
cache_controller dut (
    .clk         (clk),
    .rst_b       (rst_b),
    .addr        (addr),
    .op_read     (op_read),
    .op_write    (op_write),
    .cpu_data_in (cpu_data_in),
    .mem_data_in (mem_data_in),
    .data_out    (data_out),
    .ready       (ready),
    .mem_read    (mem_read),
    .mem_write   (mem_write),
    .mem_addr    (mem_addr),
    .evict_data  (evict_data)
);

// clock
initial clk = 0;
always #5 clk = ~clk;

//pass/fail conters
integer pass_cnt = 0;
integer fail_cnt = 0;


//for miss rate and AMAT
integer total_accesses = 0;
integer total_hits = 0;

//for miss rate
always @(posedge clk) begin
    if(op_read || op_write) begin
            total_accesses = total_accesses + 1;
            if(dut.hit)
                total_hits = total_hits + 1;
    end
end

// address
function [31:0] make_addr;
    input [18:0] tag;
    input [6:0]  index;
    input [5:0]  offset;
    begin
        make_addr = {tag, index, offset};
    end
endfunction

task check;
    input condition;
    input [127:0] test_name; 
    begin
        if (condition) begin
            $display("PASS  %s", test_name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  %s", test_name);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask


task do_read;
    input [31:0]  t_addr;
    input [511:0] t_mem_data; 
    begin
        @(negedge clk);
        addr = t_addr;
        op_read = 1'b1;
        op_write = 1'b0;
        mem_data_in = t_mem_data;

        repeat(8) begin
            @(posedge clk); #1;
            if (ready) disable do_read;
        end
    end
endtask


task do_write;
    input [31:0] t_addr;
    input [511:0] t_data;
    input [511:0] t_mem_data; 
    begin
        @(negedge clk);
        addr = t_addr;
        op_read = 1'b0;
        op_write = 1'b1;
        cpu_data_in = t_data;
        mem_data_in = t_mem_data;

        repeat(8) begin
            @(posedge clk); #1;
            if (ready) disable do_write;
        end
    end
endtask

task idle_cycle;
    begin
        @(negedge clk);
        op_read = 1'b0;
        op_write = 1'b0;
        @(posedge clk); #1;
    end
endtask

initial begin
    $display("=====================================================");
    $display("  cache_controller Testbench");
    $display("=====================================================");

    // init
    rst_b = 1'b1;
    op_read = 1'b0;
    op_write = 1'b0;
    addr = 32'd0;
    cpu_data_in = 512'd0;
    mem_data_in = 512'd0;
    
    
    // TEST 1 - Reset
    $display("\n--- TEST 1: Reset ---");
    rst_b = 1'b0;
    repeat(3) @(posedge clk);
    rst_b = 1'b1;
    @(posedge clk); #2;
    
    check(ready === 1'b0,      "ready=0 after reset");
    check(mem_read  === 1'b0,  "mem_read=0 after reset");
    check(mem_write === 1'b0,  "mem_write=0 after reset");
    
    //TEST 2 - Read miss (cold cache, clean allocate)
    $display("\n--- TEST 2: Read miss (cold cache) ---");
    @(negedge clk);
    addr        = make_addr(19'h00001, 7'd0, 6'd0);
    op_read     = 1'b1;
    op_write    = 1'b0;
    mem_data_in = 512'hAABB_CCDD; 

    @(posedge clk); #1;
    check(ready === 1'b0, "T2: not ready yet in LOOK");

    @(posedge clk); #1;
    check(ready === 1'b0, "T2: not ready in READ_MISS");

    @(posedge clk); #1;
    check(mem_read === 1'b1, "T2: mem_read asserted in ALLOCATE");
    check(ready    === 1'b1, "T2: ready asserted in ALLOCATE");
    
    @(posedge clk); #1;  
    
    $display("  T2 DEBUG: data_out[31:0]=%h  mem_data_in[31:0]=%h", data_out[31:0], mem_data_in[31:0]);
        check(data_out[31:0] === mem_data_in[31:0], "T2: data_out matches mem_data_in");

    op_read = 1'b0;
    idle_cycle;

    // TEST 3 - Read hit (same address, now in cache)
    $display("\n--- TEST 3: Read hit ---");

    @(negedge clk);
    addr     = make_addr(19'h00001, 7'd0, 6'd0);
    op_read  = 1'b1;
    op_write = 1'b0;

    @(posedge clk); #1;
    check(ready === 1'b0, "T3: not ready in LOOK");

    @(posedge clk); #1;
    check(ready    === 1'b1,  "T3: ready on READ_HIT");
    check(mem_read === 1'b0,  "T3: no mem_read on hit");
    check(data_out[31:0] === 32'hAABB_CCDD, "T3: data_out correct on hit");

    op_read = 1'b0;
    idle_cycle;

    // TEST 4 - Write hit
    $display("\n--- TEST 4: Write hit ---");

    @(negedge clk);
    addr        = make_addr(19'h00001, 7'd0, 6'd0);
    op_read     = 1'b0;
    op_write    = 1'b1;
    cpu_data_in = 512'h1234_5678;

    @(posedge clk); #1;
    check(ready === 1'b0, "T4: not ready in LOOK");

    @(posedge clk); #1;
  
    check(ready     === 1'b1, "T4: ready on WRITE_HIT");
    check(mem_write === 1'b0, "T4: no mem_write on write hit");
    check(mem_read  === 1'b0, "T4: no mem_read on write hit");

    op_write = 1'b0;
    idle_cycle;

    @(negedge clk);
    addr     = make_addr(19'h00001, 7'd0, 6'd0);
    op_read  = 1'b1;
    op_write = 1'b0;

    @(posedge clk); #1; 
    @(posedge clk); #1; 
    check(ready    === 1'b1,  "T4: read-back hit after write");
    
    @(posedge clk); #1;
    $display("  T4 DEBUG: data_out[31:0]=%h  cpu_data_in[31:0]=%h", data_out[31:0], cpu_data_in[31:0]);
    check(data_out[31:0] === cpu_data_in[31:0], "T4: read-back data matches written data");

    op_read = 1'b0;
    idle_cycle;
    
    //TEST 5 - Write miss (new address, write-allocate)
    $display("\n--- TEST 5: Write miss (write-allocate) ---");
    @(negedge clk);
    addr        = make_addr(19'h00002, 7'd0, 6'd0);
    op_read     = 1'b0;
    op_write    = 1'b1;
    cpu_data_in = 512'hDEAD_BEEF;
    mem_data_in = 512'hFFFF_0000; 

    @(posedge clk); #1;
    check(ready === 1'b0, "T5: not ready in LOOK");

    @(posedge clk); #1;
    check(ready === 1'b0, "T5: not ready in WRITE_MISS");

    @(posedge clk); #1;
    check(mem_read  === 1'b1, "T5: mem_read in ALLOCATE");
    check(mem_write === 1'b0, "T5: no mem_write (clean victim)");
    check(ready     === 1'b1, "T5: ready in ALLOCATE");

    op_write = 1'b0;
    idle_cycle;
    
    //TEST 6 - Read miss with dirty eviction
    $display("\n--- TEST 6: Read miss with dirty eviction ---");

    @(negedge clk);
    addr        = make_addr(19'h00010, 7'd1, 6'd0);
    op_write    = 1'b1;
    op_read     = 1'b0;
    cpu_data_in = 512'hCAFE_BABE;
    mem_data_in = 512'hCAFE_BABE;
    repeat(4) @(posedge clk); #1;
    op_write = 1'b0;
    idle_cycle;

    @(negedge clk);
    addr        = make_addr(19'h00010, 7'd1, 6'd0);
    op_write    = 1'b1;
    cpu_data_in = 512'hDEAD_C0DE;
    repeat(3) @(posedge clk); #1;
    op_write = 1'b0;
    idle_cycle;

    @(negedge clk);
    addr = make_addr(19'h00011, 7'd1, 6'd0); op_read=1'b1;
    mem_data_in = 512'hAAAA_1111;
    repeat(4) @(posedge clk); #1;
    op_read = 1'b0; idle_cycle;

    @(negedge clk);
    addr = make_addr(19'h00012, 7'd1, 6'd0); op_read=1'b1;
    mem_data_in = 512'hBBBB_2222;
    repeat(4) @(posedge clk); #1;
    op_read = 1'b0; idle_cycle;

    @(negedge clk);
    addr = make_addr(19'h00013, 7'd1, 6'd0); op_read=1'b1;
    mem_data_in = 512'hCCCC_3333;
    repeat(4) @(posedge clk); #1;
    op_read = 1'b0; idle_cycle;

    $display("  T6: now reading new tag at index=1, expecting EVICT then ALLOCATE");
    @(negedge clk);
    addr        = make_addr(19'h00099, 7'd1, 6'd0);
    op_read     = 1'b1;
    mem_data_in = 512'h9999_9999;

    @(posedge clk); #1;

    @(posedge clk); #1;

    @(posedge clk); #1;
    check(mem_write === 1'b1, "T6: mem_write=1 in EVICT state");
    check(mem_read  === 1'b0, "T6: mem_read=0 in EVICT state");

    @(posedge clk); #1;
    check(mem_read  === 1'b1, "T6: mem_read=1 in ALLOCATE after evict");
    check(mem_write === 1'b0, "T6: mem_write=0 in ALLOCATE");
    check(ready     === 1'b1, "T6: ready=1 in ALLOCATE");

    op_read = 1'b0;
    idle_cycle;

    
    // TEST 7 - LRU order: 4 different tags at same index
    $display("\n--- TEST 7: LRU order verification ---");

    @(negedge clk); addr=make_addr(19'h000A0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hA0A0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000B0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hB0B0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000C0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hC0C0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000D0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hD0D0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000A0,7'd5,6'd0); op_read=1'b1;
    @(posedge clk); #1; 
    @(posedge clk); #1; 
    check(ready   === 1'b1, "T7: tagA hit after re-access");
    check(mem_read === 1'b0, "T7: no mem_read on tagA re-access (hit)");
    op_read=1'b0; idle_cycle;

    @(negedge clk);
    addr        = make_addr(19'h000E0, 7'd5, 6'd0);
    op_read     = 1'b1;
    mem_data_in = 512'hE0E0;

    @(posedge clk); #1; 
    @(posedge clk); #1; 
    @(posedge clk); #1;
    check(mem_read === 1'b1, "T7: mem_read on new tag miss");
    check(ready    === 1'b1, "T7: ready after allocate");

    op_read = 1'b0;
    idle_cycle;

    $display("\n=====================================================");
    $display("  Results:  PASS=%0d   FAIL=%0d", pass_cnt, fail_cnt);
    $display("=====================================================");
    if (fail_cnt == 0)
        $display("  ALL TESTS PASSED");
    else
        $display("  SOME TESTS FAILED - check output above");
      
    $display("\n=====================================================");  
    $display("Total accesses = %0d", total_accesses);
    $display("Total hits = %0d", total_hits);
    $display("Hit Rate = %f %%", 100.0 * total_hits / total_accesses); 
    $display("Miss Rate = %f %%", 100-(100.0 * total_hits / total_accesses)); 
    $display("\n=====================================================");

    $finish;
end

endmodule
