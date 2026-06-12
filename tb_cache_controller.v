`timescale 1ns/1ps

// ============================================================
// tb_cache_controller.v
//
// Tests covered:
//   1. Reset
//   2. Read miss  (cold cache, clean allocate)
//   3. Read hit   (same address again)
//   4. Write hit  (write to address already in cache)
//   5. Write miss (cold address, write-allocate)
//   6. Read miss  with dirty eviction (EVICT -> ALLOCATE)
//   7. LRU eviction order across 4 ways
// ============================================================

module tb_cache_controller;

reg          clk;
reg          rst_b;

reg  [31:0]  addr;
reg          op_read;
reg          op_write;
reg  [511:0] cpu_data_in;
reg  [511:0] mem_data_in;

wire [511:0] data_out;
wire         ready;
wire         mem_read;
wire         mem_write;
wire [31:0]  mem_addr;
wire [511:0] evict_data;

// ----------------------------------------------------------
// DUT instantiation
// ----------------------------------------------------------
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

// ----------------------------------------------------------
// Clock: 10 ns period
// ----------------------------------------------------------
initial clk = 0;
always #5 clk = ~clk;

//Pass/fail conters
integer pass_cnt = 0;
integer fail_cnt = 0;

//Adress builder
function [31:0] make_addr;
    input [18:0] tag;
    input [6:0]  index;
    input [5:0]  offset;
    begin
        make_addr = {tag, index, offset};
    end
endfunction


task check;
    input        condition;
    input [127:0] test_name; //label printed on fail
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
    input [511:0] t_mem_data; // data memory would return
    begin
        @(negedge clk);
        addr        = t_addr;
        op_read     = 1'b1;
        op_write    = 1'b0;
        mem_data_in = t_mem_data;

        // wait until ready or timeout (8 cycles)
        repeat(8) begin
            @(posedge clk); #1;
            if (ready) disable do_read;
        end
    end
endtask


task do_write;
    input [31:0]  t_addr;
    input [511:0] t_data;
    input [511:0] t_mem_data; // in case of write miss -> allocate
    begin
        @(negedge clk);
        addr        = t_addr;
        op_read     = 1'b0;
        op_write    = 1'b1;
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
        op_read  = 1'b0;
        op_write = 1'b0;
        @(posedge clk); #1;
    end
endtask

initial begin
    $display("=====================================================");
    $display("  cache_controller Testbench");
    $display("=====================================================");

    // init
    rst_b       = 1'b1;
    op_read     = 1'b0;
    op_write    = 1'b0;
    addr        = 32'd0;
    cpu_data_in = 512'd0;
    mem_data_in = 512'd0;

    // ==========================================================
    // TEST 1 - Reset
    // ==========================================================
    $display("\n--- TEST 1: Reset ---");
    rst_b = 1'b0;
    repeat(3) @(posedge clk);
    rst_b = 1'b1;
    @(posedge clk); #2;

    // after reset FSM should be in IDLE (state=0) and ready=0
    check(ready === 1'b0,      "ready=0 after reset");
    check(mem_read  === 1'b0,  "mem_read=0 after reset");
    check(mem_write === 1'b0,  "mem_write=0 after reset");
    
    //TEST 2 - Read miss (cold cache, clean allocate)
    // addr tag=0x00001, index=0, offset=0
    // Cache is empty -> miss -> no dirty -> ALLOCATE
    // FSM: IDLE->LOOK->READ_MISS->ALLOCATE->IDLE
    // Expected: mem_read=1, then ready=1, data_out = mem_data_in
    
    $display("\n--- TEST 2: Read miss (cold cache) ---");
    @(negedge clk);
    addr        = make_addr(19'h00001, 7'd0, 6'd0);
    op_read     = 1'b1;
    op_write    = 1'b0;
    mem_data_in = 512'hAABB_CCDD; // pretend memory returns this block

    // cycle 1: IDLE -> LOOK
    @(posedge clk); #1;
    check(ready === 1'b0, "T2: not ready yet in LOOK");

    // cycle 2: LOOK -> READ_MISS
    @(posedge clk); #1;
    check(ready === 1'b0, "T2: not ready in READ_MISS");

    // cycle 3: READ_MISS -> ALLOCATE
    @(posedge clk); #1;
    check(mem_read === 1'b1, "T2: mem_read asserted in ALLOCATE");
    check(ready    === 1'b1, "T2: ready asserted in ALLOCATE");
    
    @(posedge clk); #1;  //waiting for cache_mem write to complete
    
    $display("  T2 DEBUG: data_out[31:0]=%h  mem_data_in[31:0]=%h", data_out[31:0], mem_data_in[31:0]);
        check(data_out[31:0] === mem_data_in[31:0], "T2: data_out matches mem_data_in");

    op_read = 1'b0;
    idle_cycle;

    // TEST 3 - Read hit (same address, now in cache)
    //
    // Same addr as TEST 2 -> should hit immediately
    // FSM: IDLE->LOOK->READ_HIT->IDLE
    // Expected: ready=1 after 2 cycles, no mem_read
    $display("\n--- TEST 3: Read hit ---");

    @(negedge clk);
    addr     = make_addr(19'h00001, 7'd0, 6'd0);
    op_read  = 1'b1;
    op_write = 1'b0;

    // cycle 1: IDLE -> LOOK
    @(posedge clk); #1;
    check(ready === 1'b0, "T3: not ready in LOOK");

    // cycle 2: LOOK -> READ_HIT
    @(posedge clk); #1;
    check(ready    === 1'b1,  "T3: ready on READ_HIT");
    check(mem_read === 1'b0,  "T3: no mem_read on hit");
    check(data_out[31:0] === 32'hAABB_CCDD, "T3: data_out correct on hit");

    op_read = 1'b0;
    idle_cycle;

    // TEST 4 - Write hit
    // Same address (tag=0x00001, index=0) is in cache from T2/T3.
    // Write new data -> WRITE_HIT -> cache updated, dirty=1
    // FSM: IDLE->LOOK->WRITE_HIT->IDLE
    // Expected: ready=1, cache_write asserted (internal),
    //           no mem_read, no mem_write
    
    $display("\n--- TEST 4: Write hit ---");

    @(negedge clk);
    addr        = make_addr(19'h00001, 7'd0, 6'd0);
    op_read     = 1'b0;
    op_write    = 1'b1;
    cpu_data_in = 512'h1234_5678;

    // cycle 1: IDLE -> LOOK
    @(posedge clk); #1;
    check(ready === 1'b0, "T4: not ready in LOOK");

    // cycle 2: LOOK -> WRITE_HIT
    @(posedge clk); #1;
  
    check(ready     === 1'b1, "T4: ready on WRITE_HIT");
    check(mem_write === 1'b0, "T4: no mem_write on write hit");
    check(mem_read  === 1'b0, "T4: no mem_read on write hit");

    op_write = 1'b0;
    idle_cycle;

    // verify the write actually updated cache: read back same addr
    @(negedge clk);
    addr     = make_addr(19'h00001, 7'd0, 6'd0);
    op_read  = 1'b1;
    op_write = 1'b0;

    @(posedge clk); #1; // LOOK
    @(posedge clk); #1; // READ_HIT
    check(ready    === 1'b1,  "T4: read-back hit after write");
    // wait one more cycle for cache_mem output to reflect written data
    @(posedge clk); #1;
    $display("  T4 DEBUG: data_out[31:0]=%h  cpu_data_in[31:0]=%h", data_out[31:0], cpu_data_in[31:0]);
    check(data_out[31:0] === cpu_data_in[31:0], "T4: read-back data matches written data");

    op_read = 1'b0;
    idle_cycle;
    
    //TEST 5 - Write miss (new address, write-allocate)
    // New tag=0x00002, index=0 -> miss -> clean LRU way ->
    // ALLOCATE -> write data into cache
    // FSM: IDLE->LOOK->WRITE_MISS->ALLOCATE->IDLE
    // Expected: mem_read=1 (fetch block), ready=1, no mem_write
    
    $display("\n--- TEST 5: Write miss (write-allocate) ---");
    @(negedge clk);
    addr        = make_addr(19'h00002, 7'd0, 6'd0);
    op_read     = 1'b0;
    op_write    = 1'b1;
    cpu_data_in = 512'hDEAD_BEEF;
    mem_data_in = 512'hFFFF_0000; // block from memory

    // IDLE -> LOOK
    @(posedge clk); #1;
    check(ready === 1'b0, "T5: not ready in LOOK");

    // LOOK -> WRITE_MISS
    @(posedge clk); #1;
    check(ready === 1'b0, "T5: not ready in WRITE_MISS");

    // WRITE_MISS -> ALLOCATE
    @(posedge clk); #1;
    check(mem_read  === 1'b1, "T5: mem_read in ALLOCATE");
    check(mem_write === 1'b0, "T5: no mem_write (clean victim)");
    check(ready     === 1'b1, "T5: ready in ALLOCATE");

    op_write = 1'b0;
    idle_cycle;
    
    //TEST 6 - Read miss with dirty eviction
    //
    // Fill way0 at index=1 with a dirty block, then force a miss
    // on a new tag at the same index when that way is LRU victim.
    //
    // Step A: write to tag=0x00010, index=1  -> allocates way0 (clean)
    // Step B: write-hit  same addr            -> marks way0 dirty
    // Step C: fill ways 1,2,3 at index=1 with reads (make way0 LRU)
    // Step D: read new tag=0x00011, index=1
    //         -> miss, way0 is LRU and dirty -> EVICT -> ALLOCATE
    //         -> mem_write=1 then mem_read=1
    
    $display("\n--- TEST 6: Read miss with dirty eviction ---");
    // Step A: write miss -> allocates way0 at index=1
    @(negedge clk);
    addr        = make_addr(19'h00010, 7'd1, 6'd0);
    op_write    = 1'b1;
    op_read     = 1'b0;
    cpu_data_in = 512'hCAFE_BABE;
    mem_data_in = 512'hCAFE_BABE;
    repeat(4) @(posedge clk); #1;
    op_write = 1'b0;
    idle_cycle;

    // Step B: write hit -> way0 at index=1 becomes dirty
    @(negedge clk);
    addr        = make_addr(19'h00010, 7'd1, 6'd0);
    op_write    = 1'b1;
    cpu_data_in = 512'hDEAD_C0DE;
    repeat(3) @(posedge clk); #1;
    op_write = 1'b0;
    idle_cycle;

    // Step C: read way1, way2, way3 at index=1 to make way0 the LRU
    // read tag=0x00011 -> way1
    @(negedge clk);
    addr = make_addr(19'h00011, 7'd1, 6'd0); op_read=1'b1;
    mem_data_in = 512'hAAAA_1111;
    repeat(4) @(posedge clk); #1;
    op_read = 1'b0; idle_cycle;

    // read tag=0x00012 -> way2
    @(negedge clk);
    addr = make_addr(19'h00012, 7'd1, 6'd0); op_read=1'b1;
    mem_data_in = 512'hBBBB_2222;
    repeat(4) @(posedge clk); #1;
    op_read = 1'b0; idle_cycle;

    // read tag=0x00013 -> way3
    @(negedge clk);
    addr = make_addr(19'h00013, 7'd1, 6'd0); op_read=1'b1;
    mem_data_in = 512'hCCCC_3333;
    repeat(4) @(posedge clk); #1;
    op_read = 1'b0; idle_cycle;

    // Step D: read a NEW tag at index=1 -> LRU is way0 (dirty) -> EVICT
    $display("  T6: now reading new tag at index=1, expecting EVICT then ALLOCATE");
    @(negedge clk);
    addr        = make_addr(19'h00099, 7'd1, 6'd0);
    op_read     = 1'b1;
    mem_data_in = 512'h9999_9999;

    // IDLE -> LOOK
    @(posedge clk); #1;
    // LOOK -> READ_MISS
    @(posedge clk); #1;
    // READ_MISS -> EVICT
    @(posedge clk); #1;
    check(mem_write === 1'b1, "T6: mem_write=1 in EVICT state");
    check(mem_read  === 1'b0, "T6: mem_read=0 in EVICT state");

    // EVICT -> ALLOCATE
    @(posedge clk); #1;
    check(mem_read  === 1'b1, "T6: mem_read=1 in ALLOCATE after evict");
    check(mem_write === 1'b0, "T6: mem_write=0 in ALLOCATE");
    check(ready     === 1'b1, "T6: ready=1 in ALLOCATE");

    op_read = 1'b0;
    idle_cycle;

    
    // TEST 7 - LRU order: 4 different tags at same index
    // Access order: tag A, B, C, D at index=5
    // Then access A again -> A becomes MRU, D is still LRU
    // Then access new tag E -> should evict B (LRU after A refresh)
    // We verify by checking mem_write fires (dirty eviction) or
    // simply that ready fires correctly for each access.
    
    $display("\n--- TEST 7: LRU order verification ---");

    // fill all 4 ways at index=5 with clean reads
    // access order: tagA, tagB, tagC, tagD
    // after: way0=tagA(age1), way1=tagB(age1)... actually LRU=way with highest age
    // after 4 reads: way0 age=3(LRU), way1=2, way2=1, way3=0(MRU)

    @(negedge clk); addr=make_addr(19'h000A0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hA0A0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000B0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hB0B0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000C0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hC0C0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    @(negedge clk); addr=make_addr(19'h000D0,7'd5,6'd0); op_read=1'b1; mem_data_in=512'hD0D0;
    repeat(4) @(posedge clk); #1; op_read=1'b0; idle_cycle;

    // re-access tagA -> A becomes MRU, way0 age resets to 0
    @(negedge clk); addr=make_addr(19'h000A0,7'd5,6'd0); op_read=1'b1;
    @(posedge clk); #1; // LOOK
    @(posedge clk); #1; // READ_HIT
    check(ready   === 1'b1, "T7: tagA hit after re-access");
    check(mem_read === 1'b0, "T7: no mem_read on tagA re-access (hit)");
    op_read=1'b0; idle_cycle;

    // now access a new tag -> should be a miss and evict the current LRU
    // (tagB should be LRU since A was refreshed)
    @(negedge clk);
    addr        = make_addr(19'h000E0, 7'd5, 6'd0);
    op_read     = 1'b1;
    mem_data_in = 512'hE0E0;

    @(posedge clk); #1; // LOOK
    @(posedge clk); #1; // READ_MISS
    @(posedge clk); #1; // ALLOCATE (victim was clean, no EVICT)
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

    $finish;
end

endmodule
