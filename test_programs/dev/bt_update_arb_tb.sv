`timescale 1ns/1ps

`include "src/Config.sv"
`include "src/Include.sv"

module bt_update_arb_tb;

logic clk = 0;
logic rst = 1;
BTUpdate in_updates[2:0];
BTUpdate out_update;

BTUpdateArbiter#(.NUM_IN(3)) dut
(
    .clk(clk),
    .rst(rst),
    .IN_updates(in_updates),
    .OUT_update(out_update)
);

always #5 clk = ~clk;

task automatic clear_inputs();
    for (int i = 0; i < 3; i++) begin
        in_updates[i] = '0;
        in_updates[i].valid = 0;
    end
endtask

task automatic set_update(input int idx, input logic[31:0] src, input logic[31:0] dst);
    in_updates[idx] = BTUpdate'{
        src: src,
        dst: dst,
        fetchStartOffs: '0,
        btype: BT_BRANCH,
        multipleOffs: '0,
        multiple: 0,
        compressed: 0,
        clean: 0,
        valid: 1
    };
endtask

task automatic check_update(input logic exp_valid, input logic[31:0] exp_src, input string tag);
    begin
        #1;
        if (out_update.valid !== exp_valid) begin
            $display("FAIL(%s): expected valid=%0d, got %0d", tag, exp_valid, out_update.valid);
            $fatal(1);
        end
        if (exp_valid && out_update.src !== exp_src) begin
            $display("FAIL(%s): expected src=0x%08x, got 0x%08x", tag, exp_src, out_update.src);
            $fatal(1);
        end
        $display("PASS(%s): valid=%0d src=0x%08x", tag, out_update.valid, out_update.src);
    end
endtask

initial begin
    clear_inputs();

    repeat (2) @(posedge clk);
    rst = 0;

    // Case 1: Three sources valid in same cycle.
    // Expect explicit priority (idx2 > idx1 > idx0), and no drop.
    @(negedge clk);
    clear_inputs();
    set_update(0, 32'h1000_0000, 32'h2000_0000);
    set_update(1, 32'h1000_0010, 32'h2000_0010);
    set_update(2, 32'h1000_0020, 32'h2000_0020);
    check_update(1, 32'h1000_0020, "same_cycle_0");
    @(posedge clk);

    @(negedge clk);
    clear_inputs();
    check_update(1, 32'h1000_0010, "same_cycle_1");
    @(posedge clk);

    @(negedge clk);
    clear_inputs();
    check_update(1, 32'h1000_0000, "same_cycle_2");
    @(posedge clk);

    // Case 2: While pending[idx1] is being consumed, a new idx1 update arrives.
    // Expect old pending first, then the new one in next cycle.
    @(negedge clk);
    clear_inputs();
    set_update(1, 32'h3000_0010, 32'h4000_0010);
    set_update(2, 32'h3000_0020, 32'h4000_0020);
    check_update(1, 32'h3000_0020, "pending_replace_0");
    @(posedge clk);

    @(negedge clk);
    clear_inputs();
    set_update(1, 32'h3000_00F0, 32'h4000_00F0);
    check_update(1, 32'h3000_0010, "pending_replace_1");
    @(posedge clk);

    @(negedge clk);
    clear_inputs();
    check_update(1, 32'h3000_00F0, "pending_replace_2");
    @(posedge clk);

    @(negedge clk);
    clear_inputs();
    check_update(0, '0, "drain");

    $display("RESULT_BT_ARB=PASS");
    $finish;
end

endmodule
