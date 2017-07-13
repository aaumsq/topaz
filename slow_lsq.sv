import lc3b_types::*;
`include "macros.sv"

`define Q_SIZE 8
typedef logic [3:0] lc3b_memq_id;

typedef struct packed {
	logic valid;
	lc3b_lsq_op op;
	lc3b_rob_id rob_id;
	logic addr_ready;
	lc3b_word address;
	logic val_ready;
	lc3b_word value;
	lc3b_rob_id val_rob_id;
	lc3b_word pc;
} lc3b_memq_entry;

module slow_loadstore_queue (
	input clk,
	
	lc3b_cdb data_bus,
	lc3b_cdb data_bus_out,
	
	/* New memq entry data */
	input logic new_entry,
	input lc3b_lsq_op new_op,
	input lc3b_rob_id new_rob_id,
	input lc3b_regfile_entry new_store_val,
	input lc3b_word new_pc,
	
	/* Mem signals */
	output logic read,
	output logic write,
	output logic [1:0] wmask,
	output logic [15:0] address,
	output logic [15:0] wdata,
	input logic resp,
	input logic [15:0] rdata,
	
	input lc3b_rob_id rob_head,
	input lc3b_rob_entry rob_data[`REORDER_BUFFER_SIZE],
	
	input logic flush,
	output logic full
);

/* Mem queue data */
lc3b_memq_entry memq[`Q_SIZE];
lc3b_memq_id memq_tail;

logic memq_entry_ready;
logic waiting;

initial
begin
	for(int i = 0; i < `Q_SIZE; i++)
		memq[i] = '0;
	read = 0;
	write = 0;
end

always_ff @ (posedge clk)
begin
	/* Finish memory op */
	if(resp)
	begin
		data_bus_out.dest = memq[0].rob_id;
		data_bus_out.update_pc_value = 'd0;
		data_bus_out.update_pc = 1'b0;
		data_bus_out.ready = 1;
		data_bus_out.value = rdata;
		memq[0].valid = 0;
		
		read = 0;
		write = 0;

		case(memq[0].op)
			lq_ldi: begin
				data_bus_out.ready = 0;
				memq[0].op = lq_ldr;
				memq[0].address = rdata;
				memq[0].valid = 1;
			end

			lq_ldb: begin
				if(memq[0].address[0] == 0)
					data_bus_out.value = {8'b0, rdata[7:0]};
				else
					data_bus_out.value = {8'b0, rdata[15:8]};
			end
			
			lq_trap: begin
				data_bus_out.update_pc_value = rdata;
				data_bus_out.update_pc = 1'b1;
				data_bus_out.value = memq[0].pc + 16'd2;
			end
			
			sq_sti: begin
				data_bus_out.ready = 0;
				memq[0].op = sq_str;
				memq[0].address = rdata;
				memq[0].valid = 1;
			end
			
			default: ;
		endcase
	end
	else
		data_bus_out.ready = 0;
	
	/* Put new entry into memq */
	if(new_entry && !full)
	begin
		memq[memq_tail].valid = 1;
		memq[memq_tail].op = new_op;
		memq[memq_tail].rob_id = new_rob_id;
		memq[memq_tail].addr_ready = 0;
		memq[memq_tail].pc = new_pc;

		if(new_op == lq_ldb || new_op == lq_ldi || new_op == lq_ldr || new_op == lq_trap)
			memq[memq_tail].val_ready = 1;
		else if(new_store_val.rob_id == `REORDER_ID_INVALID)
		begin
			memq[memq_tail].value = new_store_val.value;
			memq[memq_tail].val_ready = 1;
		end
		else if(data_bus.dest == new_store_val.rob_id && data_bus.ready)
		begin
			memq[memq_tail].value = data_bus.value;
			memq[memq_tail].val_ready = 1;
		end
		else
		begin
			memq[memq_tail].val_rob_id = new_store_val.rob_id;
			memq[memq_tail].val_ready = 0;
		end
	end
	
	/* Shift queue if end is done */
	if(!memq[0].valid)
	begin
		for(int i = 0; i < `Q_SIZE-1; i++)
			memq[i] = memq[i+1];
		memq[`Q_SIZE-1].valid = 0;
	end
	
	/* Snoop data off cdb */
	for(int i = 0; i < `Q_SIZE; i++)
	begin
		// Use data_bus.ready to distinguish b/w agu and alu output 
		/* Receive calculated address from cdb */
		if(memq[i].valid && (data_bus.dest == memq[i].rob_id) && !(data_bus.ready) && !(memq[i].addr_ready))
		begin
			memq[i].address = data_bus.value;
			memq[i].addr_ready = 1'b1;
		end
		/* Receive calculated store value from cdb */
		if(memq[i].valid && (data_bus.dest == memq[i].val_rob_id) && (data_bus.ready) && !(memq[i].val_ready))
		begin
			memq[i].value = data_bus.value;
			memq[i].val_ready = 1'b1;
			memq[i].val_rob_id = `REORDER_ID_INVALID;
		end
		// Get data from reorder buffer if it has valid info
		if (memq[i].valid && memq[i].val_rob_id != `REORDER_ID_INVALID &&
			rob_data[memq[i].val_rob_id].ready && rob_data[memq[i].val_rob_id].valid &&
			!memq[i].val_ready) 
		begin
			memq[i].value = rob_data[memq[i].val_rob_id].value;
			memq[i].val_ready = 1'b1;
			memq[i].val_rob_id = `REORDER_ID_INVALID;
		end
	end

	/* Send op to memory */
	if(memq_entry_ready && !waiting)
	begin
		case(memq[0].op)
			lq_ldr: begin
				read = 1;
				address = {memq[0].address[15:1], 1'b0};
			end
			
			lq_ldi: begin
				read = 1;
				address = {memq[0].address[15:1], 1'b0};
			end
			
			lq_ldb: begin
				read = 1;
				address = memq[0].address;
			end
			
			lq_trap: begin
				read = 1;
				address = memq[0].address << 16'd1;
			end
			
			sq_str: begin
				write = 1;
				address = {memq[0].address[15:1], 1'b0};
				wdata = memq[0].value;
				wmask = 2'b11;
			end
			
			sq_sti: begin
				read = 1;
				address = {memq[0].address[15:1], 1'b0};			
			end
			
			sq_stb: begin
				write = 1;
				address = {memq[0].address[15:1], 1'b0};
				wdata = {memq[0].value[7:0], memq[0].value[7:0]};
				wmask = memq[0].address[0] ? 2'b10 : 2'b01;
			end
		endcase
	end
	
	/* Flush memq */
	if(flush)
	begin
		for(int i = 0; i < `Q_SIZE; i++)
			memq[i] = '0;
		read = 0;
		write = 0; // MAKE SURE CACHE CAN DEAL WITH WRITE GOING LOW MID-WRITE
	end
end

always_comb
begin
	/* Determine whether next entry is ready */
	memq_entry_ready = 0;

	if(memq[0].valid && memq[0].addr_ready && memq[0].val_ready)
		memq_entry_ready = 1;
	
	/* Override store ready if store not at head of rob */
	if((memq[0].op == sq_str || memq[0].op == sq_stb) && memq[0].rob_id != rob_head)
		memq_entry_ready = 0;
	
	/* Find memq tail */
	memq_tail = 4'(`Q_SIZE - 1); // shouldn't need this. if queue full, no new entries can occur anyway.
	
	for(int i = 0; i < `Q_SIZE; i++)
	begin
		if(!memq[i].valid)
		begin
			memq_tail = 4'(i);
			break;
		end
		else
			memq_tail = 4'(`Q_SIZE - 1);
	end
		
	full = (memq_tail == `Q_SIZE - 1) ? '1 : '0;
	waiting = read || write;
end

endmodule : slow_loadstore_queue
