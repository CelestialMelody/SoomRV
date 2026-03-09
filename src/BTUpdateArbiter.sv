module BTUpdateArbiter
#(
    parameter NUM_IN = 2
)
(
    input wire clk,
    input wire rst,
    input BTUpdate IN_updates[NUM_IN-1:0],
    output BTUpdate OUT_update
);

localparam IDX_W = (NUM_IN <= 1) ? 1 : $clog2(NUM_IN);
typedef logic[IDX_W-1:0] SrcIdx_t;

BTUpdate pending_r[NUM_IN-1:0];
logic[NUM_IN-1:0] pendingValid_r;

BTUpdate pending_c[NUM_IN-1:0];
logic[NUM_IN-1:0] pendingValid_c;

logic selValid_c;
logic selFromPending_c;
SrcIdx_t selIdx_c;

always_comb begin
    OUT_update = '0;
    OUT_update.valid = 0;
    selValid_c = 0;
    selFromPending_c = 0;
    selIdx_c = 'x;

    // Explicit priority: higher source index has higher priority.
    // Pending updates are served before same-cycle inputs to avoid drops.
    for (integer i = NUM_IN - 1; i >= 0; i=i-1) begin
        if (!selValid_c && pendingValid_r[i]) begin
            selValid_c = 1;
            selFromPending_c = 1;
            selIdx_c = SrcIdx_t'(i);
            OUT_update = pending_r[i];
        end
    end

    for (integer i = NUM_IN - 1; i >= 0; i=i-1) begin
        if (!selValid_c && IN_updates[i].valid) begin
            selValid_c = 1;
            selFromPending_c = 0;
            selIdx_c = SrcIdx_t'(i);
            OUT_update = IN_updates[i];
        end
    end
end

always_comb begin
    for (integer i = 0; i < NUM_IN; i=i+1) begin
        pending_c[i] = pending_r[i];
    end
    pendingValid_c = pendingValid_r;

    // Selected pending entry is consumed this cycle.
    if (selValid_c && selFromPending_c) begin
        pendingValid_c[selIdx_c] = 0;
    end

    // Cache non-selected same-cycle updates (one slot per source).
    for (integer i = 0; i < NUM_IN; i=i+1) begin
        logic consumedNow;
        consumedNow = selValid_c && !selFromPending_c && (selIdx_c == SrcIdx_t'(i));
        if (IN_updates[i].valid && !consumedNow && !pendingValid_c[i]) begin
            pending_c[i] = IN_updates[i];
            pendingValid_c[i] = 1;
        end
    end
end

always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        for (integer i = 0; i < NUM_IN; i=i+1) begin
            pending_r[i] <= '0;
            pending_r[i].valid <= 0;
        end
        pendingValid_r <= '0;
    end
    else begin
        for (integer i = 0; i < NUM_IN; i=i+1) begin
            pending_r[i] <= pending_c[i];
        end
        pendingValid_r <= pendingValid_c;
    end
end

endmodule
