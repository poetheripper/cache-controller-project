`timescale 1ns/1ps

module tb_cache_mem;

    reg         clk;
    reg         rst_b;

    reg  [6:0]  index;
    reg         write_en;
    reg  [1:0]  write_way;
    reg  [18:0] tag_in;
    reg  [511:0] data_in;
    reg         valid_in;
    reg         dirty_in;

    wire [18:0] tag0,  tag1,  tag2,  tag3;
    wire        valid0, valid1, valid2, valid3;
    wire        dirty0, dirty1, dirty2, dirty3;
    wire [511:0] data0, data1, data2, data3;

    //Instantiate cache_mem
    cache_mem dut (
        .clk       (clk),
        .rst_b     (rst_b),
        .index     (index),
        .write_en  (write_en),
        .write_way (write_way),
        .tag_in    (tag_in),
        .data_in   (data_in),
        .valid_in  (valid_in),
        .dirty_in  (dirty_in),
        .tag0      (tag0),   .tag1  (tag1),   .tag2  (tag2),   .tag3  (tag3),
        .valid0    (valid0), .valid1(valid1), .valid2(valid2), .valid3(valid3),
        .dirty0    (dirty0), .dirty1(dirty1), .dirty2(dirty2), .dirty3(dirty3),
        .data0     (data0),  .data1 (data1),  .data2 (data2),  .data3 (data3)
    );

    
    initial clk = 0;
    always #5 clk = ~clk;

  
    // Pass/fail counter
    integer pass_cnt = 0;
    integer fail_cnt = 0;

   

    // task is like a function
    task do_write;
        input [6:0]   t_index;
        input [1:0]   t_way;
        input [18:0]  t_tag;
        input [511:0] t_data;
        input         t_valid;
        input         t_dirty;
        begin
            @(negedge clk);          // set inputs before rising edge
            index     = t_index;
            write_way = t_way;
            tag_in    = t_tag;
            data_in   = t_data;
            valid_in  = t_valid;
            dirty_in  = t_dirty;
            write_en  = 1'b1;
            @(posedge clk);          // latch on rising edge
            #1;                      
            write_en  = 1'b0;
        end
    endtask

    // Point the read index and wait a little for combinational outputs
    task do_read;
        input [6:0] t_index;
        begin
            @(negedge clk);
            index    = t_index;
            write_en = 1'b0;
            #1;
        end
    endtask

    // Check a single way's outputs
    task check_way;
        input [1:0]   way;
        input [18:0]  exp_tag;
        input [511:0] exp_data;
        input         exp_valid;
        input         exp_dirty;
        reg [18:0]  got_tag;
        reg [511:0] got_data;
        reg         got_valid;
        reg         got_dirty;
        begin
            case (way)
                2'd0: begin got_tag=tag0; got_data=data0; got_valid=valid0; got_dirty=dirty0; end
                2'd1: begin got_tag=tag1; got_data=data1; got_valid=valid1; got_dirty=dirty1; end
                2'd2: begin got_tag=tag2; got_data=data2; got_valid=valid2; got_dirty=dirty2; end
                2'd3: begin got_tag=tag3; got_data=data3; got_valid=valid3; got_dirty=dirty3; end
            endcase

            if (got_tag   !== exp_tag   ||
                got_data  !== exp_data  ||
                got_valid !== exp_valid ||
                got_dirty !== exp_dirty) begin
                $display("FAIL  way=%0d | tag exp=%h got=%h | valid exp=%b got=%b | dirty exp=%b got=%b | data exp=...%h got=...%h",
                         way,
                         exp_tag,   got_tag,
                         exp_valid, got_valid,
                         exp_dirty, got_dirty,
                         exp_data[31:0], got_data[31:0]);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS  way=%0d | tag=%h valid=%b dirty=%b data[31:0]=%h",
                         way, got_tag, got_valid, got_dirty, got_data[31:0]);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    
    initial begin
        $display("===================================================");
        $display("  cache_mem Testbench");
        $display("===================================================");

        //initialise inputs
        rst_b     = 1'b1;
        write_en  = 1'b0;
        index     = 7'd0;
        write_way = 2'd0;
        tag_in    = 19'd0;
        data_in   = 512'd0;
        valid_in  = 1'b0;
        dirty_in  = 1'b0;

      
        // TEST 1: Reset clears all valid & dirty bits
        $display("\n--- TEST 1: Reset ---");
        rst_b = 1'b0;           // assert reset
        repeat(3) @(posedge clk);
        #1;
        rst_b = 1'b1;           // deassert reset

        // Check a few sets after reset
        do_read(7'd0);
        if (valid0===1'b0 && valid1===1'b0 && valid2===1'b0 && valid3===1'b0) begin
            $display("PASS  set=0: all valid bits 0 after reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  set=0: valid bits not cleared after reset");
            fail_cnt = fail_cnt + 1;
        end

        do_read(7'd63);
        if (valid0===1'b0 && valid1===1'b0 && valid2===1'b0 && valid3===1'b0) begin
            $display("PASS  set=63: all valid bits 0 after reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  set=63: valid bits not cleared after reset");
            fail_cnt = fail_cnt + 1;
        end

        do_read(7'd127);
        if (valid0===1'b0 && dirty0===1'b0) begin
            $display("PASS  set=127: valid/dirty 0 after reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  set=127: valid/dirty not cleared after reset");
            fail_cnt = fail_cnt + 1;
        end

        // TEST 2:€“ Write to each of the 4 ways at set 0
        $display("\n--- TEST 2: Write all 4 ways at set 0 ---");
        do_write(7'd0, 2'd0, 19'h7_CAFE, 512'hAAAA_0000, 1'b1, 1'b0);
        do_write(7'd0, 2'd1, 19'h5_BEEF, 512'hBBBB_1111, 1'b1, 1'b1);
        do_write(7'd0, 2'd2, 19'h3_DEAD, 512'hCCCC_2222, 1'b1, 1'b0);
        do_write(7'd0, 2'd3, 19'h1_F00D, 512'hDDDD_3333, 1'b1, 1'b1);

        do_read(7'd0);
        check_way(2'd0, 19'h7_CAFE, 512'hAAAA_0000, 1'b1, 1'b0);
        check_way(2'd1, 19'h5_BEEF, 512'hBBBB_1111, 1'b1, 1'b1);
        check_way(2'd2, 19'h3_DEAD, 512'hCCCC_2222, 1'b1, 1'b0);
        check_way(2'd3, 19'h1_F00D, 512'hDDDD_3333, 1'b1, 1'b1);

    
        // TEST 3: Write to a different set (set 42) and verify
        //          set 0 is unaffected (way independence)  
        $display("\n--- TEST 3: Set independence (set 42 vs set 0) ---");
        do_write(7'd42, 2'd0, 19'h1_1111, {512{1'b1}}, 1'b1, 1'b1);
        do_write(7'd42, 2'd3, 19'h2_2222, 512'hDEAD_BEEF, 1'b1, 1'b0);

        // Verify set 42
        do_read(7'd42);
        check_way(2'd0, 19'h1_1111, {512{1'b1}},    1'b1, 1'b1);
        check_way(2'd3, 19'h2_2222, 512'hDEAD_BEEF, 1'b1, 1'b0);

        // Verify set 0 unchanged
        do_read(7'd0);
        check_way(2'd0, 19'h7_CAFE, 512'hAAAA_0000, 1'b1, 1'b0);
        check_way(2'd1, 19'h5_BEEF, 512'hBBBB_1111, 1'b1, 1'b1);

    
        // TEST 4: Overwrite a way (simulate LRU eviction / dirty update)
        $display("\n--- TEST 4: Overwrite way 1 at set 0 ---");
        do_write(7'd0, 2'd1, 19'h0_1234, 512'h9999_5678, 1'b1, 1'b1);

        do_read(7'd0);
        check_way(2'd1, 19'h0_1234, 512'h9999_5678, 1'b1, 1'b1);
        // Other ways at set 0 should be unchanged
        check_way(2'd0, 19'h7_CAFE, 512'hAAAA_0000, 1'b1, 1'b0);
        check_way(2'd2, 19'h3_DEAD, 512'hCCCC_2222, 1'b1, 1'b0);

        
        // TEST 5: write_en = 0, nothing should change
        $display("\n--- TEST 5: write_en=0 does not modify memory ---");
        @(negedge clk);
        index     = 7'd0;
        write_way = 2'd0;
        tag_in    = 19'h7_FFFF;   // different value
        data_in   = {512{1'b1}};
        valid_in  = 1'b0;
        dirty_in  = 1'b0;
        write_en  = 1'b0;         // NOT enabling write
        @(posedge clk); #1;

        do_read(7'd0);
        check_way(2'd0, 19'h7_CAFE, 512'hAAAA_0000, 1'b1, 1'b0);

      
        // TEST 6: Boundary sets: first (0) and last (127)
        $display("\n--- TEST 6: Boundary sets 0 and 127 ---");
        do_write(7'd127, 2'd0, 19'h7_FFFF, 512'h1234_5678, 1'b1, 1'b1);
        do_write(7'd127, 2'd3, 19'h0_0001, 512'hABCD_EF01, 1'b0, 1'b0);

        do_read(7'd127);
        check_way(2'd0, 19'h7_FFFF, 512'h1234_5678, 1'b1, 1'b1);
        check_way(2'd3, 19'h0_0001, 512'hABCD_EF01, 1'b0, 1'b0);

        
        // TEST 7:€“ Reset clears previously written data
        $display("\n--- TEST 7: Reset after writes ---");
        rst_b = 1'b0;
        repeat(3) @(posedge clk);
        rst_b = 1'b1;
        @(posedge clk); #2;

        // check set 0
        write_en = 1'b0;
        index = 7'd0;
        #2;
        if (valid0===1'b0 && dirty0===1'b0 &&        //if a block is invalid we don't care about the tag
            valid1===1'b0 && dirty1===1'b0) begin
            $display("PASS  set=0 cleared after second reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  set=0 | valid0=%b dirty0=%b tag0=%h valid1=%b dirty1=%b tag1=%h",
                     valid0, dirty0, tag0, valid1, dirty1, tag1);
            fail_cnt = fail_cnt + 1;
        end

        // check set 127
        index = 7'd127;
        #2;
        if (valid0===1'b0 && dirty0===1'b0) begin
            $display("PASS  set=127 cleared after second reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  set=127 | valid0=%b dirty0=%b tag0=%h",
                     valid0, dirty0, tag0);
            fail_cnt = fail_cnt + 1;
        end

        // TEST 8:  Write dirty=0 (clean block, simulates read-allocate)
        $display("\n--- TEST 8: Allocate clean block (dirty=0, valid=1) ---");
        do_write(7'd10, 2'd2, 19'h5_A5A5, 512'h0F0F_F0F0, 1'b1, 1'b0);

        do_read(7'd10);
        check_way(2'd2, 19'h5_A5A5, 512'h0F0F_F0F0, 1'b1, 1'b0);

        
        // TEST 9: Mark block dirty (simulates write-hit / write-back)
        $display("\n--- TEST 9: Mark block dirty after write-hit ---");
        do_write(7'd10, 2'd2, 19'h5_A5A5, 512'h0F0F_FFFF, 1'b1, 1'b1);

        do_read(7'd10);
        check_way(2'd2, 19'h5_A5A5, 512'h0F0F_FFFF, 1'b1, 1'b1);

      
        $display("\n===================================================");
        $display("  Results:  PASS=%0d   FAIL=%0d", pass_cnt, fail_cnt);
        $display("===================================================");

        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILE check output above");

        $finish;
    end

endmodule