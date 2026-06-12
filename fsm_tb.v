`timescale 1ns / 1ps

module fsm_tb();

    // Declararea semnalelor
    reg clk;
    reg rst_b;
    reg hit;
    reg dirty;
    reg op_read;
    reg op_write;
    
    wire [2:0] current_state;
    wire try_read, try_write, mem_read, mem_write, cache_write, ready;

    // Instantierea modulului FSM
    fsm uut (
        .clk(clk),
        .rst_b(rst_b),
        .hit(hit),
        .dirty(dirty),
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

    // Generarea semnalului de ceas (perioada de 10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Task pentru aplicarea semnalelor si asteptarea "ready"
    task issue_request;
        input is_read;
        input is_hit;
        input is_dirty;
        begin
            @(posedge clk);
            op_read = is_read;
            op_write = ~is_read;
            hit = is_hit;
            dirty = is_dirty;
            
            // Asteptam pana cand FSM-ul ridica flag-ul 'ready'
            wait(ready == 1);
            
            // Oprim request-ul
            @(posedge clk);
            op_read = 0;
            op_write = 0;
            hit = 0;
            dirty = 0;
        end
    endtask

    // Blocul principal de testare
    initial begin
        // Initializare semnale
        rst_b = 0;
        hit = 0;
        dirty = 0;
        op_read = 0;
        op_write = 0;

        // Scoatem FSM-ul din Reset
        #20;
        rst_b = 1;
        #10;

        $display("--- INCEPERE SIMULARE ---");

        // Scenariul 1: Read Hit (Ar trebui sa treaca prin IDLE -> LOOK -> READ_HIT -> IDLE)
        $display("Scenariul 1: Read Hit");
        issue_request(1'b1, 1'b1, 1'b0); 
        #20;

        // Scenariul 2: Read Miss curat (IDLE -> LOOK -> READ_MISS -> ALLOCATE -> IDLE)
        $display("Scenariul 2: Read Miss (Clean)");
        issue_request(1'b1, 1'b0, 1'b0);
        #20;

        // Scenariul 3: Read Miss dirty (IDLE -> LOOK -> READ_MISS -> EVICT -> ALLOCATE -> IDLE)
        $display("Scenariul 3: Read Miss (Dirty)");
        issue_request(1'b1, 1'b0, 1'b1);
        #20;

        // Scenariul 4: Write Hit (IDLE -> LOOK -> WRITE_HIT -> IDLE)
        $display("Scenariul 4: Write Hit");
        issue_request(1'b0, 1'b1, 1'b0);
        #20;

        // Scenariul 5: Write Miss dirty (IDLE -> LOOK -> WRITE_MISS -> EVICT -> ALLOCATE -> IDLE)
        $display("Scenariul 5: Write Miss (Dirty)");
        issue_request(1'b0, 1'b0, 1'b1);
        #20;

        $display("--- SFARSIT SIMULARE ---");
        $finish; // Opreste simularea
    end

    // Monitorizare optitionala in consola
    initial begin
        $monitor("Timp=%0t | Stare=%b | Read=%b Write=%b Hit=%b Dirty=%b | Ready=%b Mem_R=%b Mem_W=%b", 
                  $time, current_state, op_read, op_write, hit, dirty, ready, mem_read, mem_write);
    end

endmodule 