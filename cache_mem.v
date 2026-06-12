module cache_mem(

    input clk,
    input rst_b,

    // read address
    input [6:0] index,

    // write controls
    input write_en,

    input [1:0] write_way,

    input [18:0] tag_in,
    input [511:0] data_in,

    input valid_in,
    input dirty_in,

    // outputs for all 4 ways
    output wire [18:0] tag0,
    output wire [18:0] tag1,
    output wire [18:0] tag2,
    output wire [18:0] tag3,

    output wire valid0,
    output wire valid1,
    output wire valid2,
    output wire valid3,

    output wire dirty0,
    output wire dirty1,
    output wire dirty2,
    output wire dirty3,

    output wire [511:0] data0,
    output wire [511:0] data1,
    output wire [511:0] data2,
    output wire [511:0] data3

);

localparam NUM_SETS = 128;
localparam NUM_WAYS = 4;
localparam TAG_BITS = 19;
localparam DATA_BITS = 512;

reg [DATA_BITS-1:0] data_mem [0:NUM_SETS-1][0:NUM_WAYS-1];
reg [TAG_BITS-1:0]  tag_mem [0:NUM_SETS-1][0:NUM_WAYS-1];

reg valid_mem [0:NUM_SETS-1][0:NUM_WAYS-1];
reg dirty_mem [0:NUM_SETS-1][0:NUM_WAYS-1];

integer i,j;

always @(posedge clk or negedge rst_b) begin
  
    if(!rst_b) begin

        for(i=0;i<NUM_SETS;i=i+1) begin

            for(j=0;j<NUM_WAYS;j=j+1) begin

                valid_mem[i][j] <= 1'b0;
                dirty_mem[i][j] <= 1'b0;

                //tag_mem[i][j] <= 19'd0;    //Invalid lines are ignored 
                //data_mem[i][j] <= 512'd0;

            end
        end

    end

    else if(write_en) begin

        data_mem[index][write_way] <= data_in;
        tag_mem[index][write_way]  <= tag_in;

        valid_mem[index][write_way] <= valid_in;
        dirty_mem[index][write_way] <= dirty_in;

    end

end

assign tag0 = tag_mem[index][0];
assign tag1 = tag_mem[index][1];
assign tag2 = tag_mem[index][2];
assign tag3 = tag_mem[index][3];

assign valid0 = valid_mem[index][0];
assign valid1 = valid_mem[index][1];
assign valid2 = valid_mem[index][2];
assign valid3 = valid_mem[index][3];

assign dirty0 = dirty_mem[index][0];
assign dirty1 = dirty_mem[index][1];
assign dirty2 = dirty_mem[index][2];
assign dirty3 = dirty_mem[index][3];

assign data0 = data_mem[index][0];
assign data1 = data_mem[index][1];
assign data2 = data_mem[index][2];
assign data3 = data_mem[index][3];

endmodule
