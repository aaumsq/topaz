import lc3b_types::*;
`include "macros.sv"

module cpu_fetch(
	input clk,
	
	input stalled,
	
	// For dealing with control flow
	input sel_update_pc,
	input lc3b_word sel_update_pc_value,
	
	// For updating the branch predictor
	input logic rob_cf_update,
	input lc3b_word rob_cf_pc,
	input lc3b_word rob_cf_target,
	input logic [3:0] rob_cf_op,
	input rob_cf_taken,
		
	// Instruction cache memory signals
	input mem_resp_a,
   input lc3b_word mem_rdata_a,
   output logic mem_read_a,
   output mem_write_a,
   output lc3b_mem_wmask mem_byte_enable_a,
   output lc3b_word mem_address_a,
   output lc3b_word mem_wdata_a,
	
	output lc3b_word pc_out,
	output lc3b_word instruction_out,
	output logic prediction_out,
	output lc3b_word prediction_pc_out,
	output logic true_ready,
	
	input logic flush
);
logic ready;
// Program Counter
lc3b_word pc;

// Branch Predictor
logic is_control_flow;
lc3b_word target;
logic should_take;
branch_predictor predictor
(
	.clk(clk),
	
	// Update
	.update(rob_cf_update),
	.update_is_branch(rob_cf_op == `CF_BRANCH),
	.update_pc(rob_cf_pc),
	.update_taken(rob_cf_taken),
	.update_target(rob_cf_target),
	.update_op(rob_cf_op),
	
	// Need a prediction
	.pc(pc),
	.is_control_flow(is_control_flow),
	.should_take(should_take),
	.address(target)
);

// Update external pc
logic sel_update_pc_reg;
lc3b_word sel_update_pc_value_reg;

logic prev_ready;
logic was_stalled;

// Initialize
initial
begin
	sel_update_pc_reg = 1'b0;
	ready = 1'b0;
	pc = 'b0;
	was_stalled = 0;
	prev_ready = 0;
end

// PC updating logic
always_ff @(posedge clk)
begin
	// Assign the instruction, pc, and branch prediction
	if (!stalled) begin
		instruction_out = mem_rdata_a;
		pc_out = pc;
		prediction_out = is_control_flow && should_take;
		prediction_pc_out = prediction_out ? target : (pc + 16'd2);
		ready = mem_resp_a;
	end
	
	if(stalled && !was_stalled)
	begin
		prev_ready = ready;
		ready = 0;
		was_stalled = 1;
	end
	
	if(!stalled && was_stalled)
	begin
		was_stalled = 0;
		ready = prev_ready;
	end
	
	// Hold onto an external pc update
	if (sel_update_pc) begin
		sel_update_pc_reg = 1'b1;
		sel_update_pc_value_reg = sel_update_pc_value;
	end
	
	// Check if we received a response from memory
	if (!stalled && mem_resp_a) begin
		if (sel_update_pc_reg) begin
			// If we received an external pc update,
			// disregard the value read and update the pc
			sel_update_pc_reg = 1'b0;
			pc = sel_update_pc_value_reg;
			ready = 1'b0;
		end else begin
			// Otherwise, just increment the pc (take the branch if we are told to)
`ifdef BRANCH_PREDICTION_ENABLED
			pc = prediction_out ? target : (pc + 16'd2);
`else
			pc = pc + 16'd2;
`endif
		end
	end
	
	// Prevent one wrong instruction fetch if PC change right after flush
	// this is already taken care of in the above logic and doesn't account for
	// delays due to physical memory
	/*if(flush && sel_update_pc)
		ready = 1'b0;*/
end

assign true_ready = (ready && !stalled) || (prev_ready && was_stalled && !stalled);

// Don't write to the icache
assign mem_write_a = 1'b0;
assign mem_byte_enable_a = 2'b11;
assign mem_wdata_a = 16'd0;

// Memory read signals
assign mem_read_a = !stalled;
assign mem_address_a = pc;

endmodule : cpu_fetch