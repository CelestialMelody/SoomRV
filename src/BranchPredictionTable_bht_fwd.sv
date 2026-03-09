module BranchPredictionTable#(parameter IDX_LEN = `BP_BASEP_ID_LEN)
(
    input wire clk,
    input wire rst,

    input wire IN_readValid,
    input wire[IDX_LEN-1:0] IN_readAddr,
    output reg OUT_taken,

    input wire IN_writeEn,
    input wire[IDX_LEN-1:0] IN_writeAddr,
    input wire IN_writeInit,
    input wire IN_writeTaken
);

localparam NUM_COUNTERS = (1 << IDX_LEN);

reg pred[NUM_COUNTERS-1:0];
reg hist[NUM_COUNTERS-1:0];

always_ff@(posedge clk) begin
    if (IN_readValid)
        OUT_taken <= pred[IN_readAddr];
end

typedef struct packed
{
    logic[IDX_LEN-1:0] addr;
    logic taken;
    logic init;
    logic valid;
} Write;

reg[1:0] writeTempReg;

Write write_c;
Write write_r;
always_comb begin
    write_c.valid = IN_writeEn;
    write_c.init = IN_writeInit;
    write_c.addr = IN_writeAddr;
    write_c.taken = IN_writeTaken;
end

logic[IDX_LEN:0] resetIdx;

function automatic logic[1:0] nextCounter;
    input logic[1:0] cur;
    input logic taken;
    input logic init;
    begin
        nextCounter = cur;
        if (cur != 2'b11 && taken)
            nextCounter = cur + 1'b1;
        if (cur != 2'b00 && !taken)
            nextCounter = cur - 1'b1;
        if (init)
            nextCounter = {taken, !taken};
    end
endfunction

logic[1:0] writeCounterNow;
logic[1:0] writeCounterNext;
logic[1:0] writeTempFwd;
always_comb begin
    writeCounterNow = 2'b00;
    writeCounterNext = 2'b00;
    if (write_c.valid)
        writeCounterNow = {pred[write_c.addr], hist[write_c.addr]};
    if (write_r.valid)
        writeCounterNext = nextCounter(writeTempReg, write_r.taken, write_r.init);
    writeTempFwd = writeCounterNow;

    // Forward same-cycle writeback result to avoid stale read-after-write.
    if (write_c.valid && write_r.valid && write_r.addr == write_c.addr)
        writeTempFwd = writeCounterNext;
end

always_ff@(posedge clk /*or posedge rst*/) begin
    if (rst) begin
        write_r <= Write'{valid: 0, default: 'x};
        resetIdx <= 0;
        writeTempReg <= 'x;
    end
    else if (!resetIdx[IDX_LEN]) begin
        pred[resetIdx[IDX_LEN-1:0]] <= 0;
        hist[resetIdx[IDX_LEN-1:0]] <= 0;
        resetIdx <= resetIdx + 1;
    end
    else begin
        write_r <= write_c;
        if (write_c.valid) begin
            writeTempReg <= writeTempFwd;
        end
        if (write_r.valid) begin
            {pred[write_r.addr], hist[write_r.addr]} <= writeCounterNext;
        end
    end
end


endmodule
