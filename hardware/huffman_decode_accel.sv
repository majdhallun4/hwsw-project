`timescale 1ns/1ps

module huffman_decode_accel #(
    parameter int BIT_WINDOW_WIDTH = 32,
    parameter int MAX_CODE_BITS = 20,
    parameter int SYMBOL_WIDTH = 16,
    parameter int TABLE_ENTRIES = 320,
    parameter int CODE_LEN_WIDTH = $clog2(MAX_CODE_BITS + 1),
    parameter int BIT_COUNT_WIDTH = $clog2(BIT_WINDOW_WIDTH + 1),
    parameter int TABLE_ADDR_WIDTH = $clog2(TABLE_ENTRIES)
) (
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         cfg_valid,
    output logic                         cfg_ready,
    input  logic [TABLE_ADDR_WIDTH-1:0]  cfg_index,
    input  logic                         cfg_enable,
    input  logic [MAX_CODE_BITS-1:0]     cfg_code,
    input  logic [CODE_LEN_WIDTH-1:0]    cfg_code_length,
    input  logic [SYMBOL_WIDTH-1:0]      cfg_symbol,
    output logic                         cfg_error,

    input  logic                         in_valid,
    output logic                         in_ready,
    input  logic [BIT_WINDOW_WIDTH-1:0]  in_bit_window,
    input  logic [BIT_COUNT_WIDTH-1:0]   in_bit_count,

    output logic                         out_valid,
    input  logic                         out_ready,
    output logic [SYMBOL_WIDTH-1:0]      out_symbol,
    output logic [CODE_LEN_WIDTH-1:0]    out_consumed_bits,
    output logic [2:0]                   out_error
);

    localparam logic [2:0] ERR_NONE = 3'd0;
    localparam logic [2:0] ERR_NO_MATCH = 3'd1;
    localparam logic [2:0] ERR_NEED_MORE_BITS = 3'd2;
    localparam logic [2:0] ERR_TABLE = 3'd3;
    localparam logic [2:0] ERR_BIT_COUNT = 3'd4;

    logic table_valid [0:TABLE_ENTRIES-1];
    logic [MAX_CODE_BITS-1:0] table_code [0:TABLE_ENTRIES-1];
    logic [CODE_LEN_WIDTH-1:0] table_length [0:TABLE_ENTRIES-1];
    logic [SYMBOL_WIDTH-1:0] table_symbol [0:TABLE_ENTRIES-1];

    logic stage_ready;
    logic decode_found;
    logic decode_ambiguous;
    logic decode_partial;
    logic [SYMBOL_WIDTH-1:0] decode_symbol;
    logic [CODE_LEN_WIDTH-1:0] decode_length;
    logic [2:0] decode_error;
    integer decode_index;
    integer reset_index;

    function automatic logic [MAX_CODE_BITS-1:0] low_mask(input integer length);
        begin
            if (length <= 0)
                low_mask = '0;
            else if (length >= MAX_CODE_BITS)
                low_mask = '1;
            else
                low_mask = ({MAX_CODE_BITS{1'b1}} >> (MAX_CODE_BITS - length));
        end
    endfunction

    assign stage_ready = ~out_valid | out_ready;
    assign cfg_ready = stage_ready;
    assign in_ready = stage_ready & ~cfg_valid;

    always_comb begin
        decode_found = 1'b0;
        decode_ambiguous = 1'b0;
        decode_partial = 1'b0;
        decode_symbol = '0;
        decode_length = '0;

        for (decode_index = 0; decode_index < TABLE_ENTRIES; decode_index = decode_index + 1) begin
            if (table_valid[decode_index]) begin
                if (table_length[decode_index] <= in_bit_count) begin
                    if ((in_bit_window[MAX_CODE_BITS-1:0]
                            & low_mask(table_length[decode_index]))
                            == (table_code[decode_index]
                            & low_mask(table_length[decode_index]))) begin
                        if (decode_found)
                            decode_ambiguous = 1'b1;
                        if (!decode_found || table_length[decode_index] < decode_length) begin
                            decode_found = 1'b1;
                            decode_symbol = table_symbol[decode_index];
                            decode_length = table_length[decode_index];
                        end
                    end
                end else if ((in_bit_window[MAX_CODE_BITS-1:0] & low_mask(in_bit_count))
                        == (table_code[decode_index] & low_mask(in_bit_count))) begin
                    decode_partial = 1'b1;
                end
            end
        end

        decode_error = ERR_NONE;
        if (in_bit_count > BIT_WINDOW_WIDTH) begin
            decode_symbol = '0;
            decode_length = '0;
            decode_error = ERR_BIT_COUNT;
        end else if (decode_ambiguous) begin
            decode_symbol = '0;
            decode_length = '0;
            decode_error = ERR_TABLE;
        end else if (!decode_found) begin
            decode_symbol = '0;
            decode_length = '0;
            if (decode_partial)
                decode_error = ERR_NEED_MORE_BITS;
            else
                decode_error = ERR_NO_MATCH;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_symbol <= '0;
            out_consumed_bits <= '0;
            out_error <= ERR_NONE;
            cfg_error <= 1'b0;
            for (reset_index = 0; reset_index < TABLE_ENTRIES; reset_index = reset_index + 1)
                table_valid[reset_index] <= 1'b0;
        end else begin
            cfg_error <= 1'b0;
            if (stage_ready) begin
                if (cfg_valid) begin
                    out_valid <= 1'b0;
                    if (cfg_index >= TABLE_ENTRIES
                            || (cfg_enable
                            && (cfg_code_length == 0 || cfg_code_length > MAX_CODE_BITS))) begin
                        cfg_error <= 1'b1;
                    end else begin
                        table_valid[cfg_index] <= cfg_enable;
                        table_code[cfg_index] <= cfg_code;
                        table_length[cfg_index] <= cfg_code_length;
                        table_symbol[cfg_index] <= cfg_symbol;
                    end
                end else if (in_valid) begin
                    out_valid <= 1'b1;
                    out_symbol <= decode_symbol;
                    out_consumed_bits <= decode_length;
                    out_error <= decode_error;
                end else begin
                    out_valid <= 1'b0;
                end
            end
        end
    end

endmodule
