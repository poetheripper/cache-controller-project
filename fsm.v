module fsm(
   input clk,
   input rst_b,
   input hit,
   input dirty,
   input op_read,
   input op_write,
   output reg [2:0] current_state,
   output reg try_read,
   output reg try_write,
   output reg mem_read,
   output reg mem_write,
   output reg cache_write,
   output reg ready
);
   


localparam IDLE = 3'b000, // waiting for the op code
	   LOOK = 3'b001, // looks into the cache 
	   READ_HIT = 3'b010, // read hit
      	   READ_MISS = 3'b011, // read miss
	   WRITE_HIT = 3'b100, // write hit
	   WRITE_MISS = 3'b101, // write miss
	   EVICT = 3'b110, // for read/write miss LRU policy is addressed
	   ALLOCATE = 3'b111; // fetches the entire block in cache
	   

reg [2:0] state;
reg [2:0] next_state;

always @(*) begin
   current_state = state;
end


always @(posedge clk or negedge rst_b) begin
   if(!rst_b) begin
	state <= IDLE;
   end else begin
	state <= next_state;
   end

end


always @(*) begin
   next_state = state;
   try_read = 1'b0;
   try_write = 1'b0;
   mem_read = 1'b0;
   mem_write = 1'b0;
   cache_write = 1'b0;
   ready = 1'b0;

   case(state)
	IDLE: begin
	   if(op_read || op_write) begin
		try_read = op_read;
		try_write = op_write;
	  	next_state = LOOK;
	   end
	end
	
	LOOK: begin
	   if(op_read) begin
		next_state = hit ? READ_HIT : READ_MISS;
	   end else if (op_write) begin
	   	next_state = hit ? WRITE_HIT : WRITE_MISS;
	   end
	end

	READ_HIT: begin
	   ready = 1'b1;
    	   next_state = IDLE;
	end

	READ_MISS: begin
	   next_state = dirty ? EVICT : ALLOCATE;
	end

	WRITE_HIT: begin
	   cache_write = 1'b1;
	   ready  = 1'b1;
	   next_state = IDLE;
	end

	WRITE_MISS: begin
	   next_state = dirty ? EVICT : ALLOCATE;
	end

	EVICT: begin
	   mem_write = 1'b1;
	   next_state = ALLOCATE;
	end

	ALLOCATE: begin
	   mem_read = 1'b1;
	   cache_write = 1'b1;
	   ready = 1'b1;
	   next_state = IDLE;
	end

	default: begin
	   next_state = IDLE;
	end
    endcase
end
endmodule
	   

