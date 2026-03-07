`timescale 1ns/1ps
`include "HardFloat_consts.vi"

module hardfloat_ext_tb;
    localparam [2:0] RM_RNE = 3'b000;

    reg clk = 0;
    always #1 clk = ~clk;

    reg [2:0] rm = RM_RNE;

    reg [31:0] a;
    reg [31:0] b;
    wire [32:0] aRec;
    wire [32:0] bRec;
    fNToRecFN#(8, 24) toRecA(.in(a), .out(aRec));
    fNToRecFN#(8, 24) toRecB(.in(b), .out(bRec));

    wire [32:0] addRec;
    wire [4:0] addFlags;
    wire [31:0] addResult;
    addRecFN#(8, 24) addInst(
        .control(`flControl_tininessAfterRounding),
        .subOp(1'b0),
        .a(aRec),
        .b(bRec),
        .roundingMode(rm),
        .out(addRec),
        .exceptionFlags(addFlags)
    );
    recFNToFN#(8, 24) addToFn(.in(addRec), .out(addResult));

    wire [32:0] mulRec;
    wire [4:0] mulFlags;
    wire [31:0] mulResult;
    mulRecFN#(8, 24) mulInst(
        .control(`flControl_tininessAfterRounding),
        .a(aRec),
        .b(bRec),
        .roundingMode(rm),
        .out(mulRec),
        .exceptionFlags(mulFlags)
    );
    recFNToFN#(8, 24) mulToFn(.in(mulRec), .out(mulResult));

    reg [31:0] intIn;
    wire [32:0] intAsRec;
    wire [4:0] intToFpFlags;
    wire [31:0] intAsFp;
    iNToRecFN#(32, 8, 24) intToRec(
        .control(`flControl_tininessAfterRounding),
        .signedIn(1'b1),
        .in(intIn),
        .roundingMode(rm),
        .out(intAsRec),
        .exceptionFlags(intToFpFlags)
    );
    recFNToFN#(8, 24) intToFpOut(.in(intAsRec), .out(intAsFp));

    reg [31:0] fpInForInt;
    wire [32:0] fpInForIntRec;
    fNToRecFN#(8, 24) fpInRec(.in(fpInForInt), .out(fpInForIntRec));
    wire [31:0] intOut;
    wire [2:0] fpToIntFlags;
    recFNToIN#(8, 24, 32) recToInt(
        .control(`flControl_tininessAfterRounding),
        .in(fpInForIntRec),
        .roundingMode(rm),
        .signedOut(1'b1),
        .out(intOut),
        .intExceptionFlags(fpToIntFlags)
    );

    wire cmpLt;
    wire cmpEq;
    wire cmpGt;
    wire cmpUnordered;
    wire [4:0] cmpFlags;
    compareRecFN#(8, 24) cmpInst(
        .a(aRec),
        .b(bRec),
        .signaling(1'b0),
        .lt(cmpLt),
        .eq(cmpEq),
        .gt(cmpGt),
        .unordered(cmpUnordered),
        .exceptionFlags(cmpFlags)
    );

    reg divResetN = 0;
    reg divInValid = 0;
    wire divInReady;
    wire divOutValid;
    wire divSqrtOpOut;
    wire [32:0] divOutRec;
    wire [4:0] divFlags;
    wire [31:0] divResult;
    divSqrtRecFN_small#(8, 24, 0) divInst(
        .nReset(divResetN),
        .clock(clk),
        .control(`flControl_tininessAfterRounding),
        .inReady(divInReady),
        .inValid(divInValid),
        .sqrtOp(1'b0),
        .a(aRec),
        .b(bRec),
        .roundingMode(rm),
        .outValid(divOutValid),
        .sqrtOpOut(divSqrtOpOut),
        .out(divOutRec),
        .exceptionFlags(divFlags)
    );
    recFNToFN#(8, 24) divToFn(.in(divOutRec), .out(divResult));

    task expect32;
        input [31:0] got;
        input [31:0] expected;
        input [255:0] label;
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got=%08x expected=%08x", label, got, expected);
                $fatal(1);
            end
        end
    endtask

    task expect5;
        input [4:0] got;
        input [4:0] expected;
        input [255:0] label;
        begin
            if (got !== expected) begin
                $display("FAIL %0s: got=%05b expected=%05b", label, got, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        rm = RM_RNE;
        intIn = 32'd0;
        fpInForInt = 32'h00000000;
        a = 32'h00000000;
        b = 32'h00000000;

        #2;

        a = 32'h3F800000;
        b = 32'h40000000;
        #1;
        expect32(addResult, 32'h40400000, "add 1.0 + 2.0");
        expect5(addFlags, 5'b00000, "add flags");

        a = 32'h3FC00000;
        b = 32'hC0000000;
        #1;
        expect32(mulResult, 32'hC0400000, "mul 1.5 * -2.0");
        expect5(mulFlags, 5'b00000, "mul flags");

        intIn = 32'd42;
        #1;
        expect32(intAsFp, 32'h42280000, "int->fp 42");
        expect5(intToFpFlags, 5'b00000, "int->fp flags");

        fpInForInt = 32'h40800000;
        #1;
        expect32(intOut, 32'd4, "fp->int 4.0");
        if (fpToIntFlags !== 3'b000) begin
            $display("FAIL fp->int flags: got=%03b expected=000", fpToIntFlags);
            $fatal(1);
        end

        a = 32'h3F800000;
        b = 32'h3F800000;
        #1;
        if (!(cmpEq && !cmpLt && !cmpGt && !cmpUnordered && cmpFlags == 5'b00000)) begin
            $display("FAIL compare eq path");
            $fatal(1);
        end

        divResetN = 0;
        divInValid = 0;
        a = 32'h3F800000;
        b = 32'h40000000;
        repeat (2) @(posedge clk);
        divResetN = 1;

        while (!divInReady) @(posedge clk);
        divInValid = 1;
        @(posedge clk);
        divInValid = 0;

        while (!divOutValid) @(posedge clk);
        #1;
        expect32(divResult, 32'h3F000000, "div 1.0 / 2.0");
        expect5(divFlags, 5'b00000, "div flags");

        $display("PASS: hardfloat external integration smoke test");
        $finish;
    end
endmodule
