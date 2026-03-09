`timescale 1ns/1ps
`include "src/Config.sv"
`include "src/Include.sv"

`ifndef TMQ_SIZE
`define TMQ_SIZE 8
`endif

module tb;
    localparam int SIZE = `TMQ_SIZE;

    logic clk = 0;
    logic rst = 1;

    logic[$clog2(SIZE):0] free;
    logic ready;

    BranchProv branch;
    VirtMemState vmem;
    PageWalk_Res pw;
    logic pwActive;

    logic enqueue;
    logic uopReady;
    AGU_UOp in_uop;

    logic dequeue;
    AGU_UOp out_uop;

    bit fail = 0;

    TLBMissQueue #(SIZE) dut(
        .clk(clk),
        .rst(rst),
        .OUT_free(free),
        .OUT_ready(ready),
        .IN_branch(branch),
        .IN_vmem(vmem),
        .IN_pw(pw),
        .IN_pwActive(pwActive),
        .IN_enqueue(enqueue),
        .IN_uopReady(uopReady),
        .IN_uop(in_uop),
        .IN_dequeue(dequeue),
        .OUT_uop(out_uop)
    );

    always #1 clk = ~clk;

    task automatic expect_state(input int exp_free, input bit exp_ready, input int step_id);
        if (($unsigned(free) != exp_free) || (ready !== exp_ready)) begin
            $display("TMQ_CHECK_FAIL size=%0d step=%0d expect_free=%0d got_free=%0d expect_ready=%0d got_ready=%0d",
                SIZE, step_id, exp_free, free, exp_ready, ready);
            fail = 1;
        end
    endtask

    initial begin
        branch = '0;
        vmem = '0;
        pw = '0;
        pwActive = 1;
        enqueue = 0;
        uopReady = 0;
        in_uop = '0;
        dequeue = 0;

        // Keep queued uops non-ready, so they stay in queue and expose free-count behavior.
        vmem.sv32en = 1;

        repeat (2) @(posedge clk);
        rst = 0;
        @(negedge clk);

        expect_state(SIZE, 1'b1, 0);

        for (int n = 1; n <= SIZE; n++) begin
            in_uop = '0;
            in_uop.valid = 1;
            in_uop.addr = 32'h8000_0000 + (32'(n) << 12);
            in_uop.sqN = SqN'(n);
            enqueue = 1;

            @(posedge clk);
            @(negedge clk);
            enqueue = 0;
            in_uop.valid = 0;

            expect_state(SIZE - n, (n < SIZE), n);
        end

        if (fail) $display("RESULT_TMQ_PARAM=FAIL");
        else      $display("RESULT_TMQ_PARAM=PASS");
        $finish;
    end
endmodule
