`timescale 1ns/1ps
`include "src/Config.sv"
`include "src/Include.sv"

// Reproduces duplicate TLB entry insertion for identical VPN page-walk responses.
// Expected:
//   - original TLB.sv      => RESULT_DUPLICATE=1
//   - fixed TLB_fixed.sv   => RESULT_DUPLICATE=0
module tb;
    localparam int NUM_RQ = 2;
    localparam int SIZE = 8;
    localparam int ASSOC = 4;

    logic clk = 0;
    logic rst = 1;
    logic clear = 0;

    PageWalk_Res pw;
    TLB_Req rqs[NUM_RQ-1:0];
    TLB_Res res[NUM_RQ-1:0];

    TLB #(NUM_RQ, SIZE, ASSOC, 0) dut(
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .IN_pw(pw),
        .IN_rqs(rqs),
        .OUT_res(res)
    );

    always #1 clk = ~clk;

    initial begin
        int count;
        logic [19:0] vpn;
        int idx;

        vpn = 20'hABCDE;
        idx = 0; // when SIZE=8 and ASSOC=4, LEN=2, index width is 1 bit.

        pw = '0;
        for (int i = 0; i < NUM_RQ; i++) begin
            rqs[i] = '0;
        end

        repeat (2) @(posedge clk);
        rst = 0;

        // First page-walk completion: inserts one entry.
        pw.valid = 1;
        pw.busy = 0;
        pw.rqID = 2'd1; // DTLB side (IS_IFETCH=0 expects rqID!=0).
        pw.vpn = vpn;
        pw.ppn = 22'h12345;
        pw.rwx = 3'b111;
        pw.isSuperPage = 0;
        pw.user = 0;
        pw.globl = 0;
        pw.pageFault = 0;
        @(posedge clk);
        pw.valid = 0;

        // Issue one hit to move replacement pointer in the set.
        rqs[0].valid = 1;
        rqs[0].vpn = vpn;
        @(posedge clk);
        rqs[0].valid = 0;

        // Second identical page-walk completion: buggy impl may insert duplicate.
        pw.valid = 1;
        pw.busy = 0;
        pw.rqID = 2'd1;
        pw.vpn = vpn;
        pw.ppn = 22'h12345;
        pw.rwx = 3'b111;
        pw.isSuperPage = 0;
        pw.user = 0;
        pw.globl = 0;
        pw.pageFault = 0;
        @(posedge clk);
        pw.valid = 0;

        @(posedge clk);

        count = 0;
        for (int j = 0; j < ASSOC; j++) begin
            if (dut.tlb[idx][j].valid &&
                dut.tlb[idx][j].vpn == vpn[19:$clog2(SIZE / ASSOC)] &&
                dut.tlb[idx][j].isSuper == 0) begin
                count++;
            end
        end

        $display("RESULT count=%0d counter=%0d", count, dut.counters[idx]);
        if (count > 1) $display("RESULT_DUPLICATE=1");
        else           $display("RESULT_DUPLICATE=0");
        $finish;
    end
endmodule

