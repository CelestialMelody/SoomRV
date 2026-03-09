`timescale 1ns/1ps
`include "src/Config.sv"
`include "src/Include.sv"

module tb;
    localparam int NUM_IN = 1;
    localparam int NUM_EVICTED = 2;

    logic clk = 0;
    logic rst = 1;

    logic out_busy;
    LD_UOp in_uopLd[NUM_AGUS-1:0];
    StFwdResult out_fwd[NUM_AGUS-1:0];

    SQ_UOp in_uop[NUM_IN-1:0];
    logic out_stall[NUM_IN-1:0];

    logic stallSt;
    ST_UOp out_uopSt;
    ST_Ack stAck;

    bit seen_issue = 0;
    bit seen_gap = 0;

    StoreQueueBackend #(
        .NUM_IN(NUM_IN),
        .NUM_EVICTED(NUM_EVICTED)
    ) dut (
        .clk(clk),
        .rst(rst),
        .OUT_busy(out_busy),
        .IN_uopLd(in_uopLd),
        .OUT_fwd(out_fwd),
        .IN_uop(in_uop),
        .OUT_stall(out_stall),
        .IN_stallSt(stallSt),
        .OUT_uopSt(out_uopSt),
        .IN_stAck(stAck)
    );

    always #1 clk = ~clk;

    initial begin
        for (int i = 0; i < NUM_AGUS; i++)
            in_uopLd[i] = '0;

        in_uop[0] = '0;
        stallSt = 1'b1;
        stAck = '0;

        repeat (2) @(posedge clk);
        rst = 1'b0;
        @(negedge clk);

        // Inject one store and keep downstream stalled.
        in_uop[0] = '0;
        in_uop[0].valid = 1'b1;
        in_uop[0].addr = 32'h8000_0040;
        in_uop[0].data = 32'h1122_3344;
        in_uop[0].wmask = 4'b1111;
        in_uop[0].isMgmt = 1'b0;

        @(posedge clk);
        @(negedge clk);
        in_uop[0].valid = 1'b0;

        // Under continuous backpressure, optimized impl should keep valid asserted.
        repeat (20) begin
            @(posedge clk);
            @(negedge clk);

            if (out_uopSt.valid)
                seen_issue = 1'b1;

            if (seen_issue && !out_uopSt.valid)
                seen_gap = 1'b1;
        end

        if (!seen_issue)
            $display("RESULT_SQB_ISSUE=FAIL_NO_ISSUE");
        else if (seen_gap)
            $display("RESULT_SQB_ISSUE=FAIL_GAP");
        else
            $display("RESULT_SQB_ISSUE=PASS");

        $finish;
    end
endmodule
