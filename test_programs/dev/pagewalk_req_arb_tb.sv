`timescale 1ns/1ps

module pagewalk_req_arb_tb;

localparam NUM_RQS = 3;
localparam IDX_W = $clog2(NUM_RQS);

logic[NUM_RQS-1:0] valid;
logic[IDX_W-1:0] start;
logic[IDX_W-1:0] idx;
logic out_valid;

PageWalkReqArbiter#(.NUM_RQS(NUM_RQS)) dut
(
    .IN_valid(valid),
    .IN_start(start),
    .OUT_idx(idx),
    .OUT_valid(out_valid)
);

task automatic check_sel(
    input logic[NUM_RQS-1:0] in_valid,
    input logic[IDX_W-1:0] in_start,
    input logic exp_valid,
    input logic[IDX_W-1:0] exp_idx,
    input string tag
);
    begin
        valid = in_valid;
        start = in_start;
        #1;
        if (out_valid !== exp_valid) begin
            $display("FAIL(%s): expected valid=%0d, got %0d", tag, exp_valid, out_valid);
            $fatal(1);
        end
        if (exp_valid && idx !== exp_idx) begin
            $display("FAIL(%s): expected idx=%0d, got %0d", tag, exp_idx, idx);
            $fatal(1);
        end
        $display("PASS(%s): valid=%0d idx=%0d", tag, out_valid, idx);
    end
endtask

initial begin
    valid = '0;
    start = '0;

    // All sources valid: selection follows start pointer (round-robin scan order).
    check_sel(3'b111, 0, 1, 0, "all_start0");
    check_sel(3'b111, 1, 1, 1, "all_start1");
    check_sel(3'b111, 2, 1, 2, "all_start2");

    // Sparse valid set: wrap-around behavior.
    check_sel(3'b101, 0, 1, 0, "sparse_start0");
    check_sel(3'b101, 1, 1, 2, "sparse_start1");
    check_sel(3'b101, 2, 1, 2, "sparse_start2");

    // Single valid source must always be selected regardless of start.
    check_sel(3'b010, 0, 1, 1, "single_start0");
    check_sel(3'b010, 2, 1, 1, "single_start2");

    // No valid requests.
    check_sel(3'b000, 1, 0, 0, "none");

    // Demonstrates explicit policy vs legacy "last-valid-wins".
    check_sel(3'b011, 0, 1, 0, "explicit_priority");

    $display("RESULT_PAGEWALK_REQ_ARB=PASS");
    $finish;
end

endmodule
