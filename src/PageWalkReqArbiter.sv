module PageWalkReqArbiter
#(
    parameter NUM_RQS = 3
)
(
    input logic[NUM_RQS-1:0] IN_valid,
    input logic[(NUM_RQS <= 1) ? 0 : $clog2(NUM_RQS)-1:0] IN_start,
    output logic[(NUM_RQS <= 1) ? 0 : $clog2(NUM_RQS)-1:0] OUT_idx,
    output logic OUT_valid
);

localparam IDX_W = (NUM_RQS <= 1) ? 1 : $clog2(NUM_RQS);
typedef logic[IDX_W-1:0] RqIdx_t;

always_comb begin
    OUT_idx = '0;
    OUT_valid = 0;

    for (integer offs = 0; offs < NUM_RQS; offs=offs+1) begin
        integer cand;
        cand = IN_start + offs;
        if (cand >= NUM_RQS) cand = cand - NUM_RQS;
        if (!OUT_valid && IN_valid[cand]) begin
            OUT_idx = RqIdx_t'(cand);
            OUT_valid = 1;
        end
    end
end

endmodule
