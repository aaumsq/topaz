import lc3b_types::*;

`include "macros.sv"

module regfile
(
    input clk,
	 input flush,
    input load_value,
	 input load_rob,
    input lc3b_word value_in,
	 input lc3b_rob_id value_rob,
	 input lc3b_rob_id rob_in,
    input lc3b_ext_reg dest_value,
	 input lc3b_ext_reg dest_rob,
	 output lc3b_regfile_entry data[7:0] /* synthesis ramstyle = "logic" */
);

lc3b_word test_data[7:0]; // clean regfile (no rob) for testomatic

/* Altera device registers are 0 at power on. Specify this
 * so that Modelsim works as expected.
 */
initial
begin
    for (int i = 0; i < $size(data); i++)
    begin
        data[i].value = '0;
		  data[i].rob_id = `REORDER_ID_INVALID;
    end
end

always_ff @(posedge clk)
begin
    if (load_value == 1 && dest_value != `REGISTER_PC && dest_value != `DUMMY_STORE)
    begin
        data[dest_value].value = value_in;
		  // Only clear the rob id if we are getting the one we want
		  if (value_rob == data[dest_value].rob_id) begin
				data[dest_value].rob_id = `REORDER_ID_INVALID;
		  end
    end
	 
	 if (load_rob == 1 && dest_rob != `REGISTER_PC)
    begin
		  data[dest_rob].rob_id = rob_in;
    end
	 
	 // Flush everything (only make it so every register has a valid value)
	 if (flush) begin
		for (int z = 0; z < $size(data); z++) begin
			data[z].rob_id = `REORDER_ID_INVALID;
		end
	 end
end

always_comb
begin
	for(int i = 0; i < 8; i++)
		test_data[i] = data[i].value;
end

endmodule : regfile
