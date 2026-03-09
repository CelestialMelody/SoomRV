`timescale 1ns/1ps
`include "src/Config.sv"
`include "src/Include.sv"

// Reproduces duplicate insertion for superpage refill in the same set.
// Expected:
//   - TLB_fixed.sv              => RESULT_SUPER_DUPLICATE=1
//   - TLB_fixed_sp_dedup.sv     => RESULT_SUPER_DUPLICATE=0
module tb;
    localparam int NUM_RQ = 2;
    localparam int SIZE = 8;
    localparam int ASSOC = 4;
    localparam int LEN = SIZE / ASSOC;

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
        int idx;
        logic [19:0] vpn0;
        logic [19:0] vpn1;
        logic [9:0] super_key;

        // Same superpage region, same set index (bit0 unchanged), different lower VPN bits.
        vpn0 = 20'hA55AA;
        vpn1 = vpn0 ^ 20'h00002;
        idx = int'(vpn0[$clog2(LEN)-1:0]);
        super_key = vpn0[19:10];

        pw = '0;
        for (int i = 0; i < NUM_RQ; i++) begin
            rqs[i] = '0;
        end

        repeat (2) @(posedge clk);
        rst = 0;

        // First superpage refill.
        pw.valid = 1;
        pw.busy = 0;
        pw.rqID = 2'd1; // DTLB side (IS_IFETCH=0 expects rqID!=0).
        pw.vpn = vpn0;
        pw.ppn = 22'h2A000;
        pw.rwx = 3'b111;
        pw.isSuperPage = 1;
        pw.user = 0;
        pw.globl = 0;
        pw.pageFault = 0;
        @(posedge clk);
        pw.valid = 0;

        // Touch the inserted line once to advance replacement pointer.
        rqs[0].valid = 1;
        rqs[0].vpn = vpn0;
        @(posedge clk);
        rqs[0].valid = 0;

        // Second refill in same superpage region but different low VPN bits.
        pw.valid = 1;
        pw.busy = 0;
        pw.rqID = 2'd1;
        pw.vpn = vpn1;
        pw.ppn = 22'h2A000;
        pw.rwx = 3'b111;
        pw.isSuperPage = 1;
        pw.user = 0;
        pw.globl = 0;
        pw.pageFault = 0;
        @(posedge clk);
        pw.valid = 0;

        @(posedge clk);

        count = 0;
        for (int j = 0; j < ASSOC; j++) begin
            if (dut.tlb[idx][j].valid &&
                dut.tlb[idx][j].isSuper &&
                dut.tlb[idx][j].vpn[19-$clog2(LEN):10-$clog2(LEN)] == super_key) begin
                count++;
            end
        end

        $display("RESULT_SUPER count=%0d counter=%0d", count, dut.counters[idx]);
        if (count > 1) $display("RESULT_SUPER_DUPLICATE=1");
        else           $display("RESULT_SUPER_DUPLICATE=0");
        $finish;
    end
endmodule
