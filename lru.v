module lru #(
    parameter NUM_SETS = 128
)(
    input clk,
    input rst_b,

    input [6:0] index,
    input update_en,
    input [1:0] update_way,

    output reg [1:0] lru_way
);

// 2-bit age counter for each way in each set
// age=0 most recent,  age=3 least recent 
reg [1:0] age [0:NUM_SETS-1][0:3];

integer i, j;


// Update age counters on access
always @(posedge clk or negedge rst_b) begin
    if (!rst_b) begin
        // way0=0, way1=1, way2=2, way3=3
        // valid initial LRU order 
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            age[i][0] <= 2'd0;
            age[i][1] <= 2'd1;
            age[i][2] <= 2'd2;
            age[i][3] <= 2'd3;
        end
    end
    else if (update_en) begin
        // age the accessed way to 0, increment all others (cap at 3)
        if (update_way != 2'd0)
            age[index][0] <= (age[index][0] == 2'd3) ? 2'd3 : age[index][0] + 1;
        else
            age[index][0] <= 2'd0;

        if (update_way != 2'd1)
            age[index][1] <= (age[index][1] == 2'd3) ? 2'd3 : age[index][1] + 1;
        else
            age[index][1] <= 2'd0;

        if (update_way != 2'd2)
            age[index][2] <= (age[index][2] == 2'd3) ? 2'd3 : age[index][2] + 1;
        else
            age[index][2] <= 2'd0;

        if (update_way != 2'd3)
            age[index][3] <= (age[index][3] == 2'd3) ? 2'd3 : age[index][3] + 1;
        else
            age[index][3] <= 2'd0;
    end
end


// LRU victim: the way whose age == 3
always @(*) begin
    if(age[index][0] == 2'd3) lru_way = 2'd0;
    else if(age[index][1] == 2'd3) lru_way = 2'd1;
    else if (age[index][2] == 2'd3) lru_way = 2'd2;
    else                            lru_way = 2'd3;
end

endmodule
