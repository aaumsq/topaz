import lc3b_types::*;
`include "macros.sv"

module reorder_buffer
(
	input clk,
	
	// Common data bus
	lc3b_cdb data_bus,
	
	input lc3b_rs_id rs_in,
	input lc3b_ext_reg reg_in,
	input lc3b_ext_reg cc_in,
	input load,
	
	// For control flow
	input cf_update,
	input lc3b_word cf_pc,
	input lc3b_word cf_target,
	input logic [3:0] cf_op,
	input cf_taken,
	input lc3b_rob_id cf_dest,
	
	output lc3b_rob_id current_index,		// The index the next load will go to
	output logic full,
	
	output lc3b_ext_reg commit_reg,
	output lc3b_word commit_value,
	output logic commit,
	output lc3b_rob_id head,
	
	output logic rob_cf_update,
	output lc3b_word rob_cf_pc,
	output lc3b_word rob_cf_target,
	output logic [3:0] rob_cf_op,
	output logic rob_cf_taken,
	
	output lc3b_ext_reg rob_dest,
	output lc3b_rob_id reg_rob,
	output logic load_reg_rob,
	
	// Select new PC
	output logic sel_update_pc,
	output lc3b_word sel_update_pc_value,
	
	// Value to restore the CC reg to on a flush
	output lc3b_ext_reg commit_cc_reg,
	
	// Flush everything...
	output logic flush,
	
	output lc3b_rob_entry data[`REORDER_BUFFER_SIZE]
);

// Head and tail pointers
lc3b_rob_id tail;
logic [$bits(lc3b_rob_id):0] space_used;

// Make sure we get the correct default values
initial
begin
	head = 0;
	tail = 0;
	space_used = 0;
	for (int z = 0; z < `REORDER_BUFFER_SIZE; z++) begin
		data[z] = '0;
	end
end

assign current_index = tail[$bits(lc3b_rob_id)-1:0];

// Update which ROB entry we can find the most recent value of the register to load
always_comb
begin
	load_reg_rob = load && !full;
	rob_dest = reg_in;
	reg_rob = lc3b_rob_id'(tail[$bits(lc3b_rob_id)-1:0]);
end

// Add a new element in the queue when needed
always_ff @(posedge clk)
begin
	if (load && !full) begin
		data[tail].rs_id = rs_in;
		data[tail].register = reg_in;
		data[tail].value = '0;
		data[tail].update_pc_value = 'd0;
		data[tail].update_pc = 1'b0;
		data[tail].cc_reg = cc_in;
		data[tail].valid = 1'b0;
		data[tail].ready = 1'b0;
		
		data[tail].cf_update = 1'b0;
		data[tail].cf_pc = 'd0;
		data[tail].cf_target = 'd0;
		data[tail].cf_op = 'd0;
		data[tail].cf_taken = 'd0;
		
		tail = (tail == (`REORDER_BUFFER_SIZE - 1)) ? '0 : tail + 1'b1;
		space_used = space_used + 1'b1;
	end
	
	if (cf_update) begin
		data[cf_dest].cf_update = 1'b1;
		data[cf_dest].cf_pc = cf_pc;
		data[cf_dest].cf_target = cf_target;
		data[cf_dest].cf_op = cf_op;
		data[cf_dest].cf_taken = cf_taken;
	end
	
	// Set the contents of the finished instruction from the common data bus
	if (data_bus.dest != `REORDER_ID_INVALID && data[data_bus.dest].rs_id != res_invalid) begin
		data[data_bus.dest].value = data_bus.value;
		data[data_bus.dest].update_pc_value = data_bus.update_pc_value;
		data[data_bus.dest].update_pc = data_bus.update_pc;
		data[data_bus.dest].valid = 1'b1;
		data[data_bus.dest].ready = data_bus.ready;
	end
	
	// Commit (advance the head pointer)
	if (commit) begin
		/*data[head].valid = 1'b0;
		data[head].rs_id = res_invalid;*/
		data[head] = 'd0;
		head = (head == (`REORDER_BUFFER_SIZE - 1)) ? '0 : head + 1'b1;
		space_used = space_used - 1'b1;
	end
	
	// Flush the reorder buffer
	if (flush) begin
		head = 0;
		tail = 0;
		space_used = 0;
		
		for (int z = 0; z < `REORDER_BUFFER_SIZE; z++) begin
			data[z] = '0;
		end
	end
end


// Determine if we need to commit and the values that we want to commit
always_comb
begin
	commit = (data[head].valid && data[head].ready);
	commit_value = data[head].value;
	commit_reg = data[head].register;
	commit_cc_reg = data[head].cc_reg;
	
	// CF Data
	rob_cf_update = data[head].cf_update;
	rob_cf_pc = data[head].cf_pc;
	rob_cf_target = data[head].cf_target;
	rob_cf_op = data[head].cf_op;
	rob_cf_taken = data[head].cf_taken;
	
	// Flush if we need to
	flush = (data[head].valid && data[head].update_pc);
	sel_update_pc = flush;
	sel_update_pc_value = data[head].update_pc_value;
end

// Determine if we are full
always_comb
begin
	full = (space_used == `REORDER_BUFFER_SIZE);
end

endmodule : reorder_buffer