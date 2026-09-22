`timescale 1ns/1ps

module nbody_pair_accel (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     in_valid,
    output logic                     in_ready,
    input  logic signed [31:0]       in_pos_a_x,
    input  logic signed [31:0]       in_pos_a_y,
    input  logic signed [31:0]       in_pos_a_z,
    input  logic signed [31:0]       in_pos_b_x,
    input  logic signed [31:0]       in_pos_b_y,
    input  logic signed [31:0]       in_pos_b_z,
    input  logic        [31:0]       in_mass_a,
    input  logic        [31:0]       in_mass_b,
    input  logic        [31:0]       in_inv_r3,

    output logic                     out_valid,
    input  logic                     out_ready,
    output logic signed [31:0]       out_force_a_x,
    output logic signed [31:0]       out_force_a_y,
    output logic signed [31:0]       out_force_a_z,
    output logic signed [31:0]       out_force_b_x,
    output logic signed [31:0]       out_force_b_y,
    output logic signed [31:0]       out_force_b_z
);

    // Positions, masses, and outputs are Q16.16. in_inv_r3 is unsigned Q2.30.
    // The normalized force is m_a * m_b * inv_r3 * (pos_b - pos_a), with G = 1.
    localparam int OUTPUT_SHIFT = 62;
    localparam logic signed [129:0] MAX_FORCE = 130'sd2147483647;
    localparam logic signed [129:0] MIN_FORCE = -130'sd2147483647;

    logic signed [32:0] delta_x;
    logic signed [32:0] delta_y;
    logic signed [32:0] delta_z;
    logic        [63:0] mass_product;
    logic        [95:0] mass_inv_product;
    logic signed [129:0] delta_x_ext;
    logic signed [129:0] delta_y_ext;
    logic signed [129:0] delta_z_ext;
    logic signed [129:0] mass_inv_ext;
    logic signed [129:0] force_x_wide;
    logic signed [129:0] force_y_wide;
    logic signed [129:0] force_z_wide;
    logic signed [31:0] force_a_x_next;
    logic signed [31:0] force_a_y_next;
    logic signed [31:0] force_a_z_next;

    function automatic logic signed [31:0] scale_and_saturate(
        input logic signed [129:0] value
    );
        logic signed [129:0] scaled;
        begin
            scaled = value >>> OUTPUT_SHIFT;
            if (scaled > MAX_FORCE)
                scale_and_saturate = 32'sh7fff_ffff;
            else if (scaled < MIN_FORCE)
                scale_and_saturate = -32'sd2147483647;
            else
                scale_and_saturate = scaled[31:0];
        end
    endfunction

    always_comb begin
        delta_x = $signed({in_pos_b_x[31], in_pos_b_x})
                - $signed({in_pos_a_x[31], in_pos_a_x});
        delta_y = $signed({in_pos_b_y[31], in_pos_b_y})
                - $signed({in_pos_a_y[31], in_pos_a_y});
        delta_z = $signed({in_pos_b_z[31], in_pos_b_z})
                - $signed({in_pos_a_z[31], in_pos_a_z});

        mass_product = {32'b0, in_mass_a} * {32'b0, in_mass_b};
        mass_inv_product = {32'b0, mass_product} * {64'b0, in_inv_r3};

        delta_x_ext = {{97{delta_x[32]}}, delta_x};
        delta_y_ext = {{97{delta_y[32]}}, delta_y};
        delta_z_ext = {{97{delta_z[32]}}, delta_z};
        mass_inv_ext = $signed({34'b0, mass_inv_product});

        force_x_wide = delta_x_ext * mass_inv_ext;
        force_y_wide = delta_y_ext * mass_inv_ext;
        force_z_wide = delta_z_ext * mass_inv_ext;

        force_a_x_next = scale_and_saturate(force_x_wide);
        force_a_y_next = scale_and_saturate(force_y_wide);
        force_a_z_next = scale_and_saturate(force_z_wide);
    end

    assign in_ready = ~out_valid | out_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_force_a_x <= '0;
            out_force_a_y <= '0;
            out_force_a_z <= '0;
            out_force_b_x <= '0;
            out_force_b_y <= '0;
            out_force_b_z <= '0;
        end else if (in_ready) begin
            out_valid <= in_valid;
            if (in_valid) begin
                out_force_a_x <= force_a_x_next;
                out_force_a_y <= force_a_y_next;
                out_force_a_z <= force_a_z_next;
                out_force_b_x <= -force_a_x_next;
                out_force_b_y <= -force_a_y_next;
                out_force_b_z <= -force_a_z_next;
            end
        end
    end

endmodule
