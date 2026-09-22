`timescale 1ns/1ps

module tb_nbody_pair_accel;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic in_valid;
    logic in_ready;
    logic signed [31:0] in_pos_a_x;
    logic signed [31:0] in_pos_a_y;
    logic signed [31:0] in_pos_a_z;
    logic signed [31:0] in_pos_b_x;
    logic signed [31:0] in_pos_b_y;
    logic signed [31:0] in_pos_b_z;
    logic [31:0] in_mass_a;
    logic [31:0] in_mass_b;
    logic [31:0] in_inv_r3;
    logic out_valid;
    logic out_ready;
    logic signed [31:0] out_force_a_x;
    logic signed [31:0] out_force_a_y;
    logic signed [31:0] out_force_a_z;
    logic signed [31:0] out_force_b_x;
    logic signed [31:0] out_force_b_y;
    logic signed [31:0] out_force_b_z;

    always #5 clk = ~clk;

    nbody_pair_accel dut (
        .clk,
        .rst_n,
        .in_valid,
        .in_ready,
        .in_pos_a_x,
        .in_pos_a_y,
        .in_pos_a_z,
        .in_pos_b_x,
        .in_pos_b_y,
        .in_pos_b_z,
        .in_mass_a,
        .in_mass_b,
        .in_inv_r3,
        .out_valid,
        .out_ready,
        .out_force_a_x,
        .out_force_a_y,
        .out_force_a_z,
        .out_force_b_x,
        .out_force_b_y,
        .out_force_b_z
    );

    task automatic check_outputs(
        input logic signed [31:0] expected_x,
        input logic signed [31:0] expected_y,
        input logic signed [31:0] expected_z
    );
        begin
            if (!out_valid)
                $fatal(1, "N-body output was not valid");
            if (out_ready == 1'b0 && in_ready != 1'b0)
                $fatal(1, "N-body input was not backpressured by a pending output");
            if (out_force_a_x !== expected_x
                    || out_force_a_y !== expected_y
                    || out_force_a_z !== expected_z)
                $fatal(1, "N-body force A mismatch: got (%0d,%0d,%0d), expected (%0d,%0d,%0d)",
                       out_force_a_x, out_force_a_y, out_force_a_z,
                       expected_x, expected_y, expected_z);
            if (out_force_b_x !== -expected_x
                    || out_force_b_y !== -expected_y
                    || out_force_b_z !== -expected_z)
                $fatal(1, "N-body force B is not equal and opposite");
        end
    endtask

    task automatic transact(
        input logic signed [31:0] pos_a_x,
        input logic signed [31:0] pos_a_y,
        input logic signed [31:0] pos_a_z,
        input logic signed [31:0] pos_b_x,
        input logic signed [31:0] pos_b_y,
        input logic signed [31:0] pos_b_z,
        input logic        [31:0] mass_a,
        input logic        [31:0] mass_b,
        input logic        [31:0] inv_r3,
        input logic signed [31:0] expected_x,
        input logic signed [31:0] expected_y,
        input logic signed [31:0] expected_z,
        input integer stall_cycles
    );
        integer cycle;
        begin
            @(negedge clk);
            while (!in_ready)
                @(negedge clk);
            in_pos_a_x = pos_a_x;
            in_pos_a_y = pos_a_y;
            in_pos_a_z = pos_a_z;
            in_pos_b_x = pos_b_x;
            in_pos_b_y = pos_b_y;
            in_pos_b_z = pos_b_z;
            in_mass_a = mass_a;
            in_mass_b = mass_b;
            in_inv_r3 = inv_r3;
            in_valid = 1'b1;
            out_ready = 1'b0;

            @(posedge clk);
            #1;
            in_valid = 1'b0;
            check_outputs(expected_x, expected_y, expected_z);

            for (cycle = 0; cycle < stall_cycles; cycle = cycle + 1) begin
                @(posedge clk);
                #1;
                check_outputs(expected_x, expected_y, expected_z);
            end

            @(negedge clk);
            out_ready = 1'b1;
            @(posedge clk);
            #1;
            if (out_valid)
                $fatal(1, "N-body output valid did not clear after acceptance");
            out_ready = 1'b0;
        end
    endtask

    initial begin
        in_valid = 1'b0;
        out_ready = 1'b0;
        in_pos_a_x = '0;
        in_pos_a_y = '0;
        in_pos_a_z = '0;
        in_pos_b_x = '0;
        in_pos_b_y = '0;
        in_pos_b_z = '0;
        in_mass_a = '0;
        in_mass_b = '0;
        in_inv_r3 = '0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Unit masses, unit inv_r3, and displacement (1, -2, 3).
        transact(
            32'sd0, 32'sd0, 32'sd0,
            32'sd65536, -32'sd131072, 32'sd196608,
            32'd65536, 32'd65536, 32'd1073741824,
            32'sd65536, -32'sd131072, 32'sd196608,
            0
        );

        // m_a=2, m_b=3, inv_r3=0.5 gives a scalar of 3.
        transact(
            32'sd65536, -32'sd131072, 32'sd196608,
            32'sd196608, -32'sd196608, 32'sd212992,
            32'd131072, 32'd196608, 32'd536870912,
            32'sd393216, -32'sd196608, 32'sd49152,
            3
        );

        // A zero mass must produce exactly zero force.
        transact(
            -32'sd65536, 32'sd32768, 32'sd0,
            32'sd262144, -32'sd98304, 32'sd65536,
            32'd0, 32'd327680, 32'd805306368,
            32'sd0, 32'sd0, 32'sd0,
            1
        );

        // Positive saturation remains symmetric so force B is exactly -force A.
        transact(
            32'sd0, 32'sd0, 32'sd0,
            32'sh7fff_ffff, 32'sd0, 32'sd0,
            32'hffff_ffff, 32'hffff_ffff, 32'hffff_ffff,
            32'sh7fff_ffff, 32'sd0, 32'sd0,
            0
        );

        // Negative saturation uses -MAX rather than MIN_INT so negation is exact.
        transact(
            32'sd0, 32'sd0, 32'sd0,
            -32'sh7fff_ffff, 32'sd0, 32'sd0,
            32'hffff_ffff, 32'hffff_ffff, 32'hffff_ffff,
            -32'sh7fff_ffff, 32'sd0, 32'sd0,
            0
        );

        // Two consecutive transfers demonstrate one-pair-per-cycle throughput.
        @(negedge clk);
        out_ready = 1'b1;
        in_valid = 1'b1;
        in_pos_a_x = 32'sd0;
        in_pos_a_y = 32'sd0;
        in_pos_a_z = 32'sd0;
        in_pos_b_x = 32'sd65536;
        in_pos_b_y = 32'sd0;
        in_pos_b_z = 32'sd0;
        in_mass_a = 32'd65536;
        in_mass_b = 32'd65536;
        in_inv_r3 = 32'd1073741824;
        @(posedge clk);
        #1;
        check_outputs(32'sd65536, 32'sd0, 32'sd0);
        @(negedge clk);
        in_pos_b_x = 32'sd0;
        in_pos_b_y = 32'sd65536;
        @(posedge clk);
        #1;
        check_outputs(32'sd0, 32'sd65536, 32'sd0);
        @(negedge clk);
        in_valid = 1'b0;
        @(posedge clk);
        #1;
        if (out_valid)
            $fatal(1, "N-body burst output valid did not clear");
        out_ready = 1'b0;

        // Reset must discard an output that is waiting under backpressure.
        @(negedge clk);
        in_pos_b_x = 32'sd65536;
        in_mass_a = 32'd65536;
        in_mass_b = 32'd65536;
        in_inv_r3 = 32'd1073741824;
        in_valid = 1'b1;
        out_ready = 1'b0;
        @(posedge clk);
        #1;
        if (!out_valid)
            $fatal(1, "Expected pending output before reset");
        @(negedge clk);
        in_valid = 1'b0;
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        if (out_valid)
            $fatal(1, "Reset did not clear pending N-body output");
        @(negedge clk);
        rst_n = 1'b1;

        $display("PASS: tb_nbody_pair_accel");
        $finish;
    end

endmodule
