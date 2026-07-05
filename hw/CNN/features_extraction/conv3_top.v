module conv3_top #(
    parameter DATA_WIDTH   = 16,
    parameter ACCUM_WIDTH  = 32,

    parameter IMG_H        = 10,
    parameter IMG_W        = 16,

    parameter IN_CHANNELS  = 32,
    parameter OUT_CHANNELS = 64,

    parameter PIXEL_FRAC   = 8,
    parameter WEIGHT_FRAC  = 8,
    parameter OUT_FRAC     = 8,

    parameter IN_BUS_WIDTH  = IN_CHANNELS  * DATA_WIDTH,
    parameter OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH,

    parameter WEIGHT_FILE = "features.8_fused_weight.hex",
    parameter BIAS_FILE   = "features.8_fused_bias.hex"
)(
    input  wire clk,
    input  wire rst_n,

    input  wire                     in_valid,
    output wire                     in_ready,
    input  wire [IN_BUS_WIDTH-1:0]  in_pixels_flat,

    input  wire                     out_ready,
    output wire [OUT_BUS_WIDTH-1:0] out_data,
    output wire                     out_valid
);

    // =====================================================
    // 1. ROM WEIGHT & BIAS
    // =====================================================
    localparam WEIGHT_WORD_WIDTH  = DATA_WIDTH * 9;
    localparam WEIGHT_DEPTH       = OUT_CHANNELS * IN_CHANNELS; // 64*32 = 2048
    localparam INTERNAL_ACC_WIDTH = 40;

    (* rom_style = "block" *) reg [WEIGHT_WORD_WIDTH-1:0] weight_rom [0:WEIGHT_DEPTH-1];
    reg signed [ACCUM_WIDTH-1:0] bias_rom [0:OUT_CHANNELS-1];

    initial begin
        $readmemh(WEIGHT_FILE, weight_rom);
        $readmemh(BIAS_FILE,   bias_rom);
    end

    // =====================================================
    // 2. CONV3 BUFFER
    // =====================================================
    wire [IN_BUS_WIDTH-1:0] p0, p1, p2;
    wire [IN_BUS_WIDTH-1:0] p3, p4, p5;
    wire [IN_BUS_WIDTH-1:0] p6, p7, p8;

    wire buffer_out_valid;
    wire next_window_en;

    conv3_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(IN_CHANNELS),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W),
        .BUS_WIDTH(IN_BUS_WIDTH)
    ) u_buffer (
        .clk(clk),
        .rst_n(rst_n),

        .buffer_in_valid(in_valid),
        .buffer_in_ready(in_ready),
        .next_window_en(next_window_en),
        .in_pixels_512b(in_pixels_flat),

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

    // --- Width t?ng so v?i conv2_top ---
    reg [6:0] filter_idx;   // 0..63  ? 7 bits
    reg [5:0] issue_count;  // 0..31  ? 6 bits (IN_CHANNELS=32)
    reg [5:0] recv_count;   // 0..31  ? 6 bits

    reg signed [INTERNAL_ACC_WIDTH-1:0] channel_acc;
    reg [OUT_BUS_WIDTH-1:0] shift_reg;
    reg processing_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:  if (buffer_out_valid)  next_state = S_CALC;
            S_CALC:  if (processing_done)   next_state = S_SEND;
            S_SEND:  if (out_ready)         next_state = S_SLIDE;
            S_SLIDE:                        next_state = S_IDLE;
            default:                        next_state = S_IDLE;
        endcase
    end

    assign out_valid      = (state == S_SEND);
    assign out_data       = shift_reg;
    assign next_window_en = (state == S_SLIDE);

    // =====================================================
    // 4. ADDRESS CALCULATION
    // --- Gi?ng conv2_top, tính addr combinatorially ---
    // =====================================================
    wire [6:0] safe_filter_idx;
    assign safe_filter_idx =
        (filter_idx < OUT_CHANNELS) ? filter_idx : OUT_CHANNELS - 1;

    wire [5:0] ch_req;
    assign ch_req = issue_count;

    // weight_addr_req là combinatorial ? ???c dùng tr?c ti?p
    // trong registered read ? section 5 ? Vivado nh?n ra BRAM
    wire [10:0] weight_addr_req;
    assign weight_addr_req = (safe_filter_idx * IN_CHANNELS) + ch_req;
    //                        max = 63*32 + 31 = 2047 ? 11 bits ??

    wire signed [ACCUM_WIDTH-1:0] current_bias;
    assign current_bias = bias_rom[safe_filter_idx];

    // =====================================================
    // 5. ONE-CYCLE PREFETCH (gi?ng conv2_top)
    // BRAM read: ??a ch? combinatorial ? data available
    // sau 1 clock edge ? mac_en_q delay ?úng 1 cycle
    // =====================================================
    reg [WEIGHT_WORD_WIDTH-1:0] weight_word_q;
    reg mac_en_q;

    reg signed [DATA_WIDTH-1:0] p0_q, p1_q, p2_q;
    reg signed [DATA_WIDTH-1:0] p3_q, p4_q, p5_q;
    reg signed [DATA_WIDTH-1:0] p6_q, p7_q, p8_q;

    wire request_en;
    assign request_en =
        (state == S_CALC)    &&
        buffer_out_valid     &&
        !processing_done     &&
        (issue_count < IN_CHANNELS);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_word_q <= {WEIGHT_WORD_WIDTH{1'b0}};
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
            // mac_en_q = request_en delay 1 cycle
            // ? MAC nh?n data ?úng khi BRAM output valid
            mac_en_q <= request_en;

            if (request_en) begin
                // ??c BRAM b?ng ??a ch? combinatorial
                // ? Vivado nh?n ra synchronous BRAM read pattern
                weight_word_q <= weight_rom[weight_addr_req];

                // Capture pixel channel t??ng ?ng
                p0_q <= p0[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p1_q <= p1[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p2_q <= p2[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p3_q <= p3[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p4_q <= p4[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p5_q <= p5[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p6_q <= p6[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p7_q <= p7[ch_req*DATA_WIDTH +: DATA_WIDTH];
                p8_q <= p8[ch_req*DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end

    // =====================================================
    // 6. SPLIT PACKED WEIGHT WORD
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
    // 7. MAC CORE
    // =====================================================
    wire dp_partial_valid;
    wire signed [ACCUM_WIDTH-1:0] dp_partial_sum;

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
    // 8. POST-PROCESS: BIAS + ReLU + ROUND + SAT
    // current_bias l?y tr?c ti?p t? bias_rom[safe_filter_idx]
    // ? luôn ?úng filter ?ang x? lý khi dp_partial_valid
    // =====================================================
    localparam TOTAL_FRAC  = PIXEL_FRAC + WEIGHT_FRAC;
    localparam SHIFT_RIGHT = TOTAL_FRAC - OUT_FRAC;
    localparam ROUND_CONST = (1 << (SHIFT_RIGHT - 1));

    wire signed [INTERNAL_ACC_WIDTH-1:0] dp_partial_ext;
    wire signed [INTERNAL_ACC_WIDTH-1:0] bias_ext;
    wire signed [INTERNAL_ACC_WIDTH-1:0] accum_next;
    wire signed [INTERNAL_ACC_WIDTH-1:0] final_preact;

    assign dp_partial_ext =
        {{(INTERNAL_ACC_WIDTH-ACCUM_WIDTH){dp_partial_sum[ACCUM_WIDTH-1]}},
          dp_partial_sum};

    assign bias_ext =
        {{(INTERNAL_ACC_WIDTH-ACCUM_WIDTH){current_bias[ACCUM_WIDTH-1]}},
          current_bias};

    assign accum_next   = channel_acc + dp_partial_ext;
    assign final_preact = accum_next + bias_ext;

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
    // 9. CONTROL REGISTERS (gi?ng conv2_top, scale width)
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filter_idx      <= 7'd0;
            issue_count     <= 6'd0;
            recv_count      <= 6'd0;
            channel_acc     <= {INTERNAL_ACC_WIDTH{1'b0}};
            shift_reg       <= {OUT_BUS_WIDTH{1'b0}};
            processing_done <= 1'b0;
        end
        else begin
            if (state == S_IDLE) begin
                filter_idx      <= 7'd0;
                issue_count     <= 6'd0;
                recv_count      <= 6'd0;
                channel_acc     <= {INTERNAL_ACC_WIDTH{1'b0}};
                shift_reg       <= {OUT_BUS_WIDTH{1'b0}};
                processing_done <= 1'b0;
            end
            else if (state == S_CALC) begin
                // --- issue_count: mutually exclusive v?i dp_partial_valid ---
                if (dp_partial_valid && (recv_count == IN_CHANNELS - 1)) begin
                    issue_count <= 6'd0;
                end
                else if (request_en) begin
                    issue_count <= issue_count + 1'b1;
                end

                // --- Nh?n partial sum t? MAC ---
                if (dp_partial_valid) begin
                    if (recv_count == IN_CHANNELS - 1) begin
                        // Cu?i filter: l?u k?t qu?
                        shift_reg[filter_idx*DATA_WIDTH +: DATA_WIDTH]
                            <= final_pixel_calc;

                        recv_count  <= 6'd0;
                        channel_acc <= {INTERNAL_ACC_WIDTH{1'b0}};

                        if (filter_idx == OUT_CHANNELS - 1) begin
                            processing_done <= 1'b1;
                        end
                        else begin
                            filter_idx <= filter_idx + 1'b1;
                        end
                    end
                    else begin
                        channel_acc <= accum_next;
                        recv_count  <= recv_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule