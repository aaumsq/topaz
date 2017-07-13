module mp3_tb;

timeunit 1ns;
timeprecision 1ns;

logic clk;

logic mem_resp;
logic mem_read;
logic mem_write;
logic [1:0] mem_byte_enable;
logic [15:0] mem_address;
logic [127:0] mem_rdata;
logic [127:0] mem_wdata;

/* Clock generator */
initial clk = 0;
always #5 clk = ~clk;

mp3 dut
(
    .clk,
	 
    .mem_resp,
    .mem_rdata,
    .mem_read,
    .mem_write,
    .mem_byte_enable,
    .mem_address,
    .mem_wdata
);

/*
magic_memory_dp memory
(
    .clk,
	 
    .read_a(mem_read_a),
    .write_a(mem_write_a),
    .wmask_a(mem_byte_enable_a),
    .address_a(mem_address_a),
    .wdata_a(mem_wdata_a),
    .resp_a(mem_resp_a),
    .rdata_a(mem_rdata_a),
	 
	.read_b(mem_read_b),
    .write_b(mem_write_b),
    .wmask_b(mem_byte_enable_b),
    .address_b(mem_address_b),
    .wdata_b(mem_wdata_b),
    .resp_b(mem_resp_b),
    .rdata_b(mem_rdata_b)
);
*/

physical_memory memory
(
	.clk,
	
	.read(mem_read),
    .write(mem_write),
    .address(mem_address),
    .wdata(mem_wdata),
    .resp(mem_resp),
    .rdata(mem_rdata)
);

endmodule : mp3_tb
