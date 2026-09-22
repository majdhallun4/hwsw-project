`timescale 1ns/1ps

module tb_huffman_decode_accel;

    localparam int BIT_WINDOW_WIDTH = 32;
    localparam int MAX_CODE_BITS = 20;
    localparam int SYMBOL_WIDTH = 16;
    localparam int TABLE_ENTRIES = 6;
    localparam int CODE_LEN_WIDTH = $clog2(MAX_CODE_BITS + 1);
    localparam int BIT_COUNT_WIDTH = $clog2(BIT_WINDOW_WIDTH + 1);
    localparam int TABLE_ADDR_WIDTH = $clog2(TABLE_ENTRIES);

    localparam logic [2:0] ERR_NONE = 3'd0;
    localparam logic [2:0] ERR_NO_MATCH = 3'd1;
    localparam logic [2:0] ERR_NEED_MORE_BITS = 3'd2;
    localparam logic [2:0] ERR_TABLE = 3'd3;
    localparam logic [2:0] ERR_BIT_COUNT = 3'd4;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic cfg_valid;
    logic cfg_ready;
    logic [TABLE_ADDR_WIDTH-1:0] cfg_index;
    logic cfg_enable;
    logic [MAX_CODE_BITS-1:0] cfg_code;
    logic [CODE_LEN_WIDTH-1:0] cfg_code_length;
    logic [SYMBOL_WIDTH-1:0] cfg_symbol;
    logic cfg_error;
    logic in_valid;
    logic in_ready;
    logic [BIT_WINDOW_WIDTH-1:0] in_bit_window;
    logic [BIT_COUNT_WIDTH-1:0] in_bit_count;
    logic out_valid;
    logic out_ready;
    logic [SYMBOL_WIDTH-1:0] out_symbol;
    logic [CODE_LEN_WIDTH-1:0] out_consumed_bits;
    logic [2:0] out_error;

    always #5 clk = ~clk;

    huffman_decode_accel #(
        .BIT_WINDOW_WIDTH(BIT_WINDOW_WIDTH),
        .MAX_CODE_BITS(MAX_CODE_BITS),
        .SYMBOL_WIDTH(SYMBOL_WIDTH),
        .TABLE_ENTRIES(TABLE_ENTRIES)
    ) dut (
        .clk,
        .rst_n,
        .cfg_valid,
        .cfg_ready,
        .cfg_index,
        .cfg_enable,
        .cfg_code,
        .cfg_code_length,
        .cfg_symbol,
        .cfg_error,
        .in_valid,
        .in_ready,
        .in_bit_window,
        .in_bit_count,
        .out_valid,
        .out_ready,
        .out_symbol,
        .out_consumed_bits,
        .out_error
    );

    task automatic configure(
        input logic [TABLE_ADDR_WIDTH-1:0] index,
        input logic enable,
        input logic [MAX_CODE_BITS-1:0] code,
        input logic [CODE_LEN_WIDTH-1:0] length,
        input logic [SYMBOL_WIDTH-1:0] symbol,
        input logic expected_error
    );
        begin
            @(negedge clk);
            while (!cfg_ready)
                @(negedge clk);
            cfg_index = index;
            cfg_enable = enable;
            cfg_code = code;
            cfg_code_length = length;
            cfg_symbol = symbol;
            cfg_valid = 1'b1;
            @(posedge clk);
            #1;
            cfg_valid = 1'b0;
            if (cfg_error !== expected_error)
                $fatal(1, "Configuration error mismatch at index %0d", index);
        end
    endtask

    task automatic check_decode(
        input logic [SYMBOL_WIDTH-1:0] expected_symbol,
        input logic [CODE_LEN_WIDTH-1:0] expected_length,
        input logic [2:0] expected_error
    );
        begin
            if (!out_valid)
                $fatal(1, "Huffman output was not valid");
            if (out_ready == 1'b0 && (in_ready != 1'b0 || cfg_ready != 1'b0))
                $fatal(1, "Huffman interfaces were not backpressured by a pending output");
            if (out_symbol !== expected_symbol
                    || out_consumed_bits !== expected_length
                    || out_error !== expected_error)
                $fatal(1, "Huffman mismatch: symbol=%0d length=%0d error=%0d",
                       out_symbol, out_consumed_bits, out_error);
        end
    endtask

    task automatic decode(
        input logic [BIT_WINDOW_WIDTH-1:0] bit_window,
        input logic [BIT_COUNT_WIDTH-1:0] bit_count,
        input logic [SYMBOL_WIDTH-1:0] expected_symbol,
        input logic [CODE_LEN_WIDTH-1:0] expected_length,
        input logic [2:0] expected_error,
        input integer stall_cycles
    );
        integer cycle;
        begin
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            in_bit_window = bit_window;
            in_bit_count = bit_count;
            in_valid = 1'b1;
            out_ready = 1'b0;
            @(posedge clk);
            #1;
            in_valid = 1'b0;
            check_decode(expected_symbol, expected_length, expected_error);

            for (cycle = 0; cycle < stall_cycles; cycle = cycle + 1) begin
                @(posedge clk);
                #1;
                check_decode(expected_symbol, expected_length, expected_error);
            end

            @(negedge clk);
            out_ready = 1'b1;
            @(posedge clk);
            #1;
            if (out_valid)
                $fatal(1, "Huffman output valid did not clear after acceptance");
            out_ready = 1'b0;
        end
    endtask

    initial begin
        cfg_valid = 1'b0;
        cfg_index = '0;
        cfg_enable = 1'b0;
        cfg_code = '0;
        cfg_code_length = '0;
        cfg_symbol = '0;
        in_valid = 1'b0;
        in_bit_window = '0;
        in_bit_count = '0;
        out_ready = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Codes are stored in transmission order, with the next stream bit in bit 0:
        // A=0, B=10, C=110, D=111.
        configure(3'd0, 1'b1, 20'b0,   5'd1, 16'd65, 1'b0);
        configure(3'd1, 1'b1, 20'b001, 5'd2, 16'd66, 1'b0);
        configure(3'd2, 1'b1, 20'b011, 5'd3, 16'd67, 1'b0);
        configure(3'd3, 1'b1, 20'b111, 5'd3, 16'd68, 1'b0);

        decode(32'hffff_fffe, 6'd20, 16'd65, 5'd1, ERR_NONE, 0);
        decode(32'h1234_5601, 6'd16, 16'd66, 5'd2, ERR_NONE, 1);
        decode(32'h0000_0003, 6'd3, 16'd67, 5'd3, ERR_NONE, 3);
        decode(32'h0000_0007, 6'd3, 16'd68, 5'd3, ERR_NONE, 0);

        // The prefix 11 is valid but requires one more bit.
        decode(32'h0000_0003, 6'd2, 16'd0, 5'd0, ERR_NEED_MORE_BITS, 0);

        // Removing D leaves 111 as a definite invalid code.
        configure(3'd3, 1'b0, 20'd0, 5'd0, 16'd0, 1'b0);
        decode(32'h0000_0007, 6'd3, 16'd0, 5'd0, ERR_NO_MATCH, 0);

        // A duplicate transmission code is reported as a table error.
        configure(3'd4, 1'b1, 20'b001, 5'd2, 16'd99, 1'b0);
        decode(32'h0000_0001, 6'd2, 16'd0, 5'd0, ERR_TABLE, 0);
        configure(3'd4, 1'b0, 20'd0, 5'd0, 16'd0, 1'b0);

        // Two consecutive requests demonstrate one-window-per-cycle throughput.
        @(negedge clk);
        out_ready = 1'b1;
        in_valid = 1'b1;
        in_bit_window = 32'h0000_0001;
        in_bit_count = 6'd2;
        @(posedge clk);
        #1;
        check_decode(16'd66, 5'd2, ERR_NONE);
        @(negedge clk);
        in_bit_window = 32'h0000_0003;
        in_bit_count = 6'd3;
        @(posedge clk);
        #1;
        check_decode(16'd67, 5'd3, ERR_NONE);
        @(negedge clk);
        in_valid = 1'b0;
        @(posedge clk);
        #1;
        if (out_valid)
            $fatal(1, "Huffman burst output valid did not clear");
        out_ready = 1'b0;

        // Invalid configuration writes are rejected and reported.
        configure(3'd5, 1'b1, 20'd0, 5'd0, 16'd70, 1'b1);
        configure(3'd7, 1'b1, 20'd0, 5'd1, 16'd71, 1'b1);
        decode(32'h0000_0001, 6'd2, 16'd66, 5'd2, ERR_NONE, 0);

        // A count larger than the physical window is an explicit request error.
        decode(32'h0000_0000, 6'd33, 16'd0, 5'd0, ERR_BIT_COUNT, 0);

        // Reset discards a stalled output and clears the programmed table.
        @(negedge clk);
        in_bit_window = 32'h0000_0001;
        in_bit_count = 6'd2;
        in_valid = 1'b1;
        out_ready = 1'b0;
        @(posedge clk);
        #1;
        if (!out_valid)
            $fatal(1, "Expected pending Huffman output before reset");
        @(negedge clk);
        in_valid = 1'b0;
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        if (out_valid)
            $fatal(1, "Reset did not clear pending Huffman output");
        @(negedge clk);
        rst_n = 1'b1;
        decode(32'h0000_0001, 6'd2, 16'd0, 5'd0, ERR_NO_MATCH, 0);

        $display("PASS: tb_huffman_decode_accel");
        $finish;
    end

endmodule
