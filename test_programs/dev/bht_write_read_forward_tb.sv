`timescale 1ns/1ps
`include "src/Config.sv"
`include "src/Include.sv"

module tb;
    localparam int IDX_LEN = 2;
    localparam int TRAIN_CYCLES = 2;
    localparam logic[IDX_LEN-1:0] TRAIN_ADDR = 2'b01;

    logic clk = 0;
    logic rst = 1;

    logic readValid;
    logic[IDX_LEN-1:0] readAddr;
    logic out_taken;

    logic writeEn;
    logic[IDX_LEN-1:0] writeAddr;
    logic writeInit;
    logic writeTaken;

    BranchPredictionTable #(
        .IDX_LEN(IDX_LEN)
    ) dut (
        .clk(clk),
        .rst(rst),
        .IN_readValid(readValid),
        .IN_readAddr(readAddr),
        .OUT_taken(out_taken),
        .IN_writeEn(writeEn),
        .IN_writeAddr(writeAddr),
        .IN_writeInit(writeInit),
        .IN_writeTaken(writeTaken)
    );

    always #1 clk = ~clk;

    initial begin
        readValid = 1'b0;
        readAddr = '0;
        writeEn = 1'b0;
        writeAddr = '0;
        writeInit = 1'b0;
        writeTaken = 1'b0;

        repeat (2) @(posedge clk);
        rst = 1'b0;

        // Wait for internal array reset walk to complete.
        repeat ((1 << IDX_LEN) + 2) @(posedge clk);

        // Back-to-back training to the same index stresses write-after-read behavior.
        for (int i = 0; i < TRAIN_CYCLES; i++) begin
            @(negedge clk);
            writeEn = 1'b1;
            writeAddr = TRAIN_ADDR;
            writeInit = 1'b0;
            writeTaken = 1'b1;
            @(posedge clk);
        end

        @(negedge clk);
        writeEn = 1'b0;

        // Flush pipeline update stage.
        repeat (2) @(posedge clk);

        @(negedge clk);
        readValid = 1'b1;
        readAddr = TRAIN_ADDR;
        @(posedge clk);

        @(negedge clk);
        readValid = 1'b0;
        @(posedge clk);

        if (out_taken === 1'b1)
            $display("RESULT_BHT_FWD=PASS");
        else if (out_taken === 1'b0)
            $display("RESULT_BHT_FWD=FAIL_STALE");
        else
            $display("RESULT_BHT_FWD=FAIL_X");

        $finish;
    end
endmodule
