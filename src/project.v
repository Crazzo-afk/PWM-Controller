/*
 * Copyright (c) 2024 YYJR
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_pwm_8ch_10b (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    assign uio_oe       = 8'b1000_0000;
    assign uio_out[6:0] = 7'b0;

    wire [2:0] ch    = uio_in[2:0];
    wire [1:0] reg_sel   = uio_in[4:3];  // 00: duty[7:0], 01: duty[9:8], 10: prescaler[3:0]
    wire       wr_raw    = uio_in[5];
    wire       en = uio_in[6];
    wire _unused = &{ena, uio_in[7], ui_in[7:4], 1'b0};

    // Write-enable synchronizer + rising-edge detect
    reg [2:0] wr_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) wr_sync <= 3'b0;
        else        wr_sync <= {wr_sync[1:0], wr_raw};
    wire wr_pulse = (wr_sync[2:1] == 2'b01);

    // Duty storage: no reset. Write every channel before enabling.
    reg [7:0] duty_lo [0:7];
    reg [1:0] duty_hi [0:7];
    reg [3:0] pre_reg;

    always @(posedge clk) begin
        if (wr_pulse) begin
            case (reg_sel)
                2'b00: duty_lo[ch] <= ui_in;
                2'b01: duty_hi[ch] <= ui_in[1:0];
                default: ;
            endcase
        end
    end
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                          pre_reg <= 4'd0;
        else if (wr_pulse && reg_sel == 2'b10) pre_reg <= ui_in[3:0];

    // Scan counter, prescaler, PWM counter
    reg [2:0] scan;
    reg [3:0] pre_cnt;
    reg [9:0] pwm_cnt;
    wire slot_end = (scan == 3'd7);
    wire pwm_tick = slot_end && (pre_cnt == pre_reg);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || !en) begin
            scan <= 3'd0; pre_cnt <= 4'd0; pwm_cnt <= 10'd0;
        end else begin
            scan <= scan + 3'd1;
            if (slot_end) begin
                if (pre_cnt == pre_reg) begin
                    pre_cnt <= 4'd0;
                    pwm_cnt <= pwm_cnt + 10'd1;
                end else
                    pre_cnt <= pre_cnt + 4'd1;
            end
        end
    end

    // One shared comparator, one channel per clock
    wire [9:0] duty_sel = {duty_hi[scan], duty_lo[scan]};
    reg  [7:0] pwm_out;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || !en) pwm_out <= 8'b0;
        else                      pwm_out[scan] <= (pwm_cnt < duty_sel);
    end

    assign uo_out     = pwm_out;
    assign uio_out[7] = pwm_tick && (&pwm_cnt) && en;  // end-of-period pulse
endmodule
