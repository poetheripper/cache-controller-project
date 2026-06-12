module hit_detector(
    input [18:0] addr_tag,
    input [18:0] tag0,
    input [18:0] tag1,
    input [18:0] tag2,
    input [18:0] tag3,
    input valid0,
    input valid1,
    input valid2,
    input valid3,
    output hit,
    output reg [1:0] hit_way
);

wire hit0;
wire hit1;
wire hit2;
wire hit3;

assign hit0 = valid0 && (tag0 == addr_tag);
assign hit1 = valid1 && (tag1 == addr_tag);
assign hit2 = valid2 && (tag2 == addr_tag);
assign hit3 = valid3 && (tag3 == addr_tag);

assign hit = hit0 | hit1 | hit2 | hit3;

always @(*) begin
    if(hit0)
        hit_way = 2'd0;
    else if(hit1)
        hit_way = 2'd1;
    else if(hit2)
        hit_way = 2'd2;
    else if(hit3)
        hit_way = 2'd3;
    else
        hit_way = 2'd0;
end

endmodule
