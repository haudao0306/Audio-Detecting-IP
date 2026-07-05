module conv_top #(
    parameter DATA_WIDTH   = 16,
    parameter ACCUM_WIDTH  = 32,

    parameter IMG_H        = 40,
    parameter IMG_W        = 64,

    parameter IN_CHANNELS  = 1,
    parameter OUT_CHANNELS = 16,

    parameter PIXEL_FRAC   = 10,
    parameter WEIGHT_FRAC  = 8,
    parameter OUT_FRAC     = 8,

    parameter IN_BUS_WIDTH  = IN_CHANNELS  * DATA_WIDTH,
    parameter OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH,

    parameter WEIGHT_FILE = "features.0_fused_weight.hex",
    parameter BIAS_FILE   = "features.0_fused_bias.hex"
)(
    input  wire clk,
    input  wire rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [DATA_WIDTH-1:0] in_pixel,

    input  wire                     out_ready,
    output wire [OUT_BUS_WIDTH-1:0] out_data,
    output wire                     out_valid,

    output wire [DATA_WIDTH*9-1:0] dbg_weight_word_q,
    output wire [ACCUM_WIDTH-1:0]  dbg_dp_partial_sum,
    output wire [ACCUM_WIDTH-1:0]  dbg_bias_q,
    output wire [39:0]             dbg_final_preact,
    output wire [DATA_WIDTH-1:0]   dbg_final_pixel_calc
);

    // =====================================================
    // 1. ROM WEIGHT & BIAS
    // =====================================================
    localparam WEIGHT_WORD_WIDTH  = DATA_WIDTH * 9;  // 144 bits
    localparam WEIGHT_DEPTH       = OUT_CHANNELS * IN_CHANNELS; // 16
    localparam INTERNAL_ACC_WIDTH = 40;

    (* rom_style = "block" *) reg [WEIGHT_WORD_WIDTH-1:0] weight_rom [0:WEIGHT_DEPTH-1];
    reg signed [ACCUM_WIDTH-1:0] bias_rom [0:OUT_CHANNELS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weight_rom);
        $readmemh(BIAS_FILE,   bias_rom);
    end

    // =====================================================
    // 2. CONV BUFFER
    // =====================================================
    wire signed [DATA_WIDTH-1:0] p0, p1, p2;
    wire signed [DATA_WIDTH-1:0] p3, p4, p5;
    wire signed [DATA_WIDTH-1:0] p6, p7, p8;

    wire buffer_out_valid;
    wire next_window_en;

    conv_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W)
    ) u_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .buffer_in_valid(in_valid),
        .buffer_in_ready(in_ready),
        .next_window_en(next_window_en),
        .in_pixel(in_pixel),

        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),

        .buffer_out_valid(buffer_out_valid)
    );

    // =====================================================
    // 3. FSM
    // =====================================================
    localparam S_IDLE  = 2'd0;
    localparam S_CALC  = 2'd1;
    localparam S_SEND  = 2'd2;
    localparam S_SLIDE = 2'd3;

    reg [1:0] state, next_state;

    reg [4:0] filter_idx;
    reg       processing_done;
    reg [OUT_BUS_WIDTH-1:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:  if (buffer_out_valid) next_state = S_CALC;
            S_CALC:  if (processing_done)  next_state = S_SEND;
            S_SEND:  if (out_ready)        next_state = S_SLIDE;
            S_SLIDE:                       next_state = S_IDLE;
            default:                       next_state = S_IDLE;
        endcase
    end

    assign out_valid      = (state == S_SEND);
    assign out_data       = shift_reg;
    assign next_window_en = (state == S_SLIDE);

    // =====================================================
    // 4. ADDRESS & BIAS
    // =====================================================
    wire [4:0] safe_filter_idx;
    assign safe_filter_idx =
        (filter_idx < OUT_CHANNELS) ? filter_idx : OUT_CHANNELS - 1;

    wire [3:0] weight_addr_req;
    assign weight_addr_req = safe_filter_idx[3:0];

    // =====================================================
    // 5. MAC BUSY
    // =====================================================
    reg mac_busy;

    wire dp_partial_valid;
    wire signed [ACCUM_WIDTH-1:0] dp_partial_sum;

    wire request_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mac_busy <= 1'b0;
        else begin
            if (dp_partial_valid)
                mac_busy <= 1'b0;
            else if (request_en)
                mac_busy <= 1'b1;
        end
    end

    // =====================================================
    // 6. ONE-CYCLE PREFETCH
    // =====================================================
    reg [WEIGHT_WORD_WIDTH-1:0] weight_word_q;
    reg signed [ACCUM_WIDTH-1:0] bias_q;
    reg mac_en_q;

    reg signed [DATA_WIDTH-1:0] p0_q, p1_q, p2_q;
    reg signed [DATA_WIDTH-1:0] p3_q, p4_q, p5_q;
    reg signed [DATA_WIDTH-1:0] p6_q, p7_q, p8_q;

    assign request_en =
        (state == S_CALC)   &&
        buffer_out_valid    &&
        !processing_done    &&
        !mac_busy           &&
        (filter_idx < OUT_CHANNELS);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_word_q <= {WEIGHT_WORD_WIDTH{1'b0}};
            bias_q        <= {ACCUM_WIDTH{1'b0}};
            mac_en_q      <= 1'b0;
            p0_q <= {DATA_WIDTH{1'b0}};
            p1_q <= {DATA_WIDTH{1'b0}};
            p2_q <= {DATA_WIDTH{1'b0}};
            p3_q <= {DATA_WIDTH{1'b0}};
            p4_q <= {DATA_WIDTH{1'b0}};
            p5_q <= {DATA_WIDTH{1'b0}};
            p6_q <= {DATA_WIDTH{1'b0}};
            p7_q <= {DATA_WIDTH{1'b0}};
            p8_q <= {DATA_WIDTH{1'b0}};
        end
        else begin
            mac_en_q <= request_en;

            if (request_en) begin
                weight_word_q <= weight_rom[weight_addr_req];
                bias_q <= bias_rom[safe_filter_idx];

                p0_q <= p0; p1_q <= p1; p2_q <= p2;
                p3_q <= p3; p4_q <= p4; p5_q <= p5;
                p6_q <= p6; p7_q <= p7; p8_q <= p8;
            end
        end
    end

    // =====================================================
    // 7. SPLIT PACKED WEIGHT WORD
    // =====================================================
    wire signed [DATA_WIDTH-1:0] w0_ch, w1_ch, w2_ch;
    wire signed [DATA_WIDTH-1:0] w3_ch, w4_ch, w5_ch;
    wire signed [DATA_WIDTH-1:0] w6_ch, w7_ch, w8_ch;

    assign w0_ch = weight_word_q[15:0];
    assign w1_ch = weight_word_q[31:16];
    assign w2_ch = weight_word_q[47:32];
    assign w3_ch = weight_word_q[63:48];
    assign w4_ch = weight_word_q[79:64];
    assign w5_ch = weight_word_q[95:80];
    assign w6_ch = weight_word_q[111:96];
    assign w7_ch = weight_word_q[127:112];
    assign w8_ch = weight_word_q[143:128];

    // =====================================================
    // 8. MAC CORE
    // =====================================================
    conv_mac9 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .en(mac_en_q),

        .p0(p0_q), .p1(p1_q), .p2(p2_q),
        .p3(p3_q), .p4(p4_q), .p5(p5_q),
        .p6(p6_q), .p7(p7_q), .p8(p8_q),

        .w0(w0_ch), .w1(w1_ch), .w2(w2_ch),
        .w3(w3_ch), .w4(w4_ch), .w5(w5_ch),
        .w6(w6_ch), .w7(w7_ch), .w8(w8_ch),

        .partial_sum(dp_partial_sum),
        .partial_valid(dp_partial_valid)
    );

    // =====================================================
    // 9. POST-PROCESS: BIAS + ReLU + ROUND + SAT
    // =====================================================
    localparam TOTAL_FRAC  = PIXEL_FRAC + WEIGHT_FRAC;
    localparam SHIFT_RIGHT = TOTAL_FRAC - OUT_FRAC;
    localparam ROUND_CONST = (1 << (SHIFT_RIGHT - 1));

    wire signed [INTERNAL_ACC_WIDTH-1:0] dp_partial_ext;
    wire signed [INTERNAL_ACC_WIDTH-1:0] bias_ext;
    wire signed [INTERNAL_ACC_WIDTH-1:0] final_preact;

    assign dp_partial_ext =
        {{(INTERNAL_ACC_WIDTH-ACCUM_WIDTH){dp_partial_sum[ACCUM_WIDTH-1]}},
          dp_partial_sum};

    assign bias_ext =
        {{(INTERNAL_ACC_WIDTH-ACCUM_WIDTH){bias_q[ACCUM_WIDTH-1]}},
          bias_q};

    assign final_preact = dp_partial_ext + bias_ext;

    function [DATA_WIDTH-1:0] quant_relu_sat;
        input signed [INTERNAL_ACC_WIDTH-1:0] din;
        reg signed [INTERNAL_ACC_WIDTH-1:0] relu_val;
        reg        [INTERNAL_ACC_WIDTH-1:0] rounded;
        begin
            if (din > 0)
                relu_val = din;
            else
                relu_val = {INTERNAL_ACC_WIDTH{1'b0}};

            rounded = relu_val + ROUND_CONST;

            if (|rounded[INTERNAL_ACC_WIDTH-2 : DATA_WIDTH + SHIFT_RIGHT - 1])
                quant_relu_sat = 16'h7FFF;
            else
                quant_relu_sat = rounded[DATA_WIDTH + SHIFT_RIGHT - 1 : SHIFT_RIGHT];
        end
    endfunction

    wire [DATA_WIDTH-1:0] final_pixel_calc;
    assign final_pixel_calc = quant_relu_sat(final_preact);

    // =====================================================
    // 10. CONTROL REGISTERS
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filter_idx      <= 5'd0;
            shift_reg       <= {OUT_BUS_WIDTH{1'b0}};
            processing_done <= 1'b0;
        end
        else begin
            if (state == S_IDLE) begin
                filter_idx      <= 5'd0;
                shift_reg       <= {OUT_BUS_WIDTH{1'b0}};
                processing_done <= 1'b0;
            end
            else if (state == S_CALC) begin
                if (dp_partial_valid) begin
                    shift_reg[filter_idx*DATA_WIDTH +: DATA_WIDTH]
                        <= final_pixel_calc;

                    if (filter_idx == OUT_CHANNELS - 1) begin
                        processing_done <= 1'b1;
                    end
                    else begin
                        filter_idx <= filter_idx + 1'b1;
                    end
                end
            end
        end
    end

    // =====================================================
    // 11. DEBUG OUTPUTS
    // =====================================================
    assign dbg_weight_word_q     = weight_word_q;
    assign dbg_dp_partial_sum    = dp_partial_sum;
    assign dbg_bias_q            = bias_q;
    assign dbg_final_preact      = final_preact;
    assign dbg_final_pixel_calc  = final_pixel_calc;

endmodule
