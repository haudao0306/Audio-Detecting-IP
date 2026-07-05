module classifier_layer2 #(
    parameter DATA_WIDTH  = 16,
    parameter IN_NODES    = 128,
    parameter OUT_CLASSES = 3,
    parameter BATCH_SIZE  = 64,       // = IN_NODES / 2, kh?p DSP layer1
    parameter NUM_BATCHES = 2,        // IN_NODES / BATCH_SIZE
    parameter ACCUM_WIDTH = 40,
    parameter Q_FRAC      = 8,

    localparam IN_BUS       = IN_NODES  * DATA_WIDTH,  // 2048 bit
    localparam BATCH_BUS    = BATCH_SIZE * DATA_WIDTH, // 1024 bit
    localparam NUM_PASSES   = OUT_CLASSES * NUM_BATCHES // 6
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Giao th?c Valid/Ready cho Input
    input  wire                 in_valid,
    output wire                 in_ready,
    input  wire [IN_BUS-1:0]    in_layer1_data,

    // Output
    output reg                  out_valid,
    output reg  signed [15:0]   out_class_0,
    output reg  signed [15:0]   out_class_1,
    output reg  signed [15:0]   out_class_2
);

    // =========================================================
    // FSM STATES DECLARATION (??a lên ??u ?? dùng cho in_ready)
    // =========================================================
    localparam S_IDLE   = 3'd0;
    localparam S_ISSUE  = 3'd1;
    localparam S_WAIT   = 3'd2;
    localparam S_ACCUM  = 3'd3;
    localparam S_OUTPUT = 3'd4;

    reg [2:0] state, next_state;

    // =========================================================
    // 1. ROM
    //    weight: 2048bit × 3 ? LUTRAM (nh?, không c?n BRAM)
    //    bias  : 16bit   × 3 ? registers
    // =========================================================
    reg [IN_BUS-1:0]           weight_rom [0:OUT_CLASSES-1];
    reg signed [DATA_WIDTH-1:0] bias_rom  [0:OUT_CLASSES-1];

    initial begin
        $readmemh("classifier.3_weight.hex", weight_rom);
        $readmemh("classifier.3_bias.hex",   bias_rom);
    end

    // =========================================================
    // 2. INPUT REGISTER & VALID/READY HANDSHAKE
    // =========================================================
    reg [IN_BUS-1:0] data_reg;
    reg              data_valid;

    // Logic in_ready: Ch? s?n sàng khi FSM ?ang r?nh và data c? ?ã x? lý xong
    assign in_ready = (state == S_IDLE) && !data_valid;
    
    // input_fire: Xác nh?n data h?p l? ???c ??a vào thành công
    wire input_fire = in_valid && in_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_reg   <= {IN_BUS{1'b0}};
            data_valid <= 1'b0;
        end
        else begin
            // Ch? capture data khi có s? ??ng thu?n t? c? 2 phía (valid & ready)
            if (input_fire) begin
                data_reg   <= in_layer1_data;
                data_valid <= 1'b1;
            end
            else if (state == S_OUTPUT) begin // Xóa c? an toàn khi ?ã tính xong
                data_valid <= 1'b0;
            end
        end
    end

    // =========================================================
    // 3. FSM
    // =========================================================
    // pass_idx: 0..5
    // class_idx = pass_idx / 2  (0,0,1,1,2,2)
    // batch_idx = pass_idx % 2  (0,1,0,1,0,1)
    reg [2:0] pass_idx;

    wire [1:0] class_idx = pass_idx[2:1];   // pass_idx >> 1
    wire       batch_idx = pass_idx[0];     // pass_idx & 1

    wire last_pass = (pass_idx == NUM_PASSES - 1);

    // Pipeline drain counter (2 cycles sau S_ISSUE)
    reg [1:0] wait_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_IDLE;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:   if (data_valid)       next_state = S_ISSUE;
            S_ISSUE:                        next_state = S_WAIT;
            S_WAIT:   if (wait_cnt == 2'd1) next_state = S_ACCUM;
            S_ACCUM:  if (last_pass)        next_state = S_OUTPUT;
                      else                  next_state = S_ISSUE;
            S_OUTPUT:                       next_state = S_IDLE;
            default:                        next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pass_idx <= 3'd0;
            wait_cnt <= 2'd0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    pass_idx <= 3'd0;
                end

                S_ISSUE: begin
                    wait_cnt <= 2'd0;
                end

                S_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                end

                S_ACCUM: begin
                    if (!last_pass)
                        pass_idx <= pass_idx + 1'b1;
                end

                S_OUTPUT: begin
                    pass_idx <= 3'd0;
                end
            endcase
        end
    end

    // =========================================================
    // 4. BATCH SLICE
    // =========================================================
    wire [BATCH_BUS-1:0] data_batch = 
        batch_idx ? data_reg[IN_BUS-1 : BATCH_BUS]
                  : data_reg[BATCH_BUS-1 : 0];

    wire [BATCH_BUS-1:0] weight_batch = 
        batch_idx ? weight_rom[class_idx][IN_BUS-1 : BATCH_BUS]
                  : weight_rom[class_idx][BATCH_BUS-1 : 0];

    // =========================================================
    // 5. MAC STAGE 1: 64 multipliers
    // =========================================================
    reg signed [31:0]        mult_reg [0:BATCH_SIZE-1];
    reg                      mac_valid_s1;
    reg [1:0]                class_idx_s1;
    reg                      batch_idx_s1;

    wire mac_en = (state == S_ISSUE);

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_valid_s1  <= 1'b0;
            class_idx_s1  <= 2'd0;
            batch_idx_s1  <= 1'b0;
            for (k = 0; k < BATCH_SIZE; k = k + 1)
                mult_reg[k] <= 32'sd0;
        end
        else begin
            mac_valid_s1 <= mac_en;
            class_idx_s1 <= class_idx;
            batch_idx_s1 <= batch_idx;

            if (mac_en) begin
                for (k = 0; k < BATCH_SIZE; k = k + 1) begin
                    mult_reg[k] <= 
                        $signed(data_batch  [k*DATA_WIDTH +: DATA_WIDTH]) *
                        $signed(weight_batch[k*DATA_WIDTH +: DATA_WIDTH]);
                end
            end
        end
    end

    // =========================================================
    // 6. MAC STAGE 2: adder tree 64?1 + accumulate
    // =========================================================
    reg signed [ACCUM_WIDTH-1:0] accum_reg [0:OUT_CLASSES-1];
    reg                          accum_valid;
    reg [1:0]                    class_idx_s2;

    integer i;
    reg signed [ACCUM_WIDTH-1:0] tree_sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_valid  <= 1'b0;
            class_idx_s2 <= 2'd0;
            for (i = 0; i < OUT_CLASSES; i = i + 1)
                accum_reg[i] <= {ACCUM_WIDTH{1'b0}};
        end
        else begin
            accum_valid  <= mac_valid_s1;
            class_idx_s2 <= class_idx_s1;

            if (mac_valid_s1) begin
                // Adder tree: c?ng 64 products
                tree_sum = {ACCUM_WIDTH{1'b0}};
                for (i = 0; i < BATCH_SIZE; i = i + 1)
                    tree_sum = tree_sum + 
                        {{(ACCUM_WIDTH-32){mult_reg[i][31]}}, mult_reg[i]};
                
                // Accumulate
                if (batch_idx_s1 == 1'b0)
                    accum_reg[class_idx_s1] <= tree_sum;
                else
                    accum_reg[class_idx_s1] <= accum_reg[class_idx_s1] + tree_sum;
            end
        end
    end

    // =========================================================
    // 7. OUTPUT STAGE: bias + rounding + signed saturation
    // =========================================================
    function [15:0] bias_round_sat;
        input signed [ACCUM_WIDTH-1:0] acc;
        input signed [DATA_WIDTH-1:0]  bias;
        reg signed [ACCUM_WIDTH-1:0] with_bias;
        reg signed [ACCUM_WIDTH-1:0] rounded;
        reg [16:0]                   upper;
        begin
            // Bias Q8 ? align lên Q16
            with_bias = acc + 
                ($signed({{(ACCUM_WIDTH-DATA_WIDTH){bias[DATA_WIDTH-1]}}, bias}) 
                 <<< Q_FRAC);

            // Rounding +0.5 LSB
            rounded = with_bias + (40'd1 << (Q_FRAC - 1));

            // Signed saturation
            upper = rounded[ACCUM_WIDTH-1 : DATA_WIDTH + Q_FRAC - 1];  

            if (upper == 17'h00000)
                bias_round_sat = rounded[DATA_WIDTH + Q_FRAC - 1 : Q_FRAC];
            else if (upper == 17'h1FFFF)
                bias_round_sat = rounded[DATA_WIDTH + Q_FRAC - 1 : Q_FRAC];
            else if (rounded[ACCUM_WIDTH-1] == 1'b0)
                bias_round_sat = 16'h7FFF;
            else
                bias_round_sat = 16'h8000;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid   <= 1'b0;
            out_class_0 <= 16'sd0;
            out_class_1 <= 16'sd0;
            out_class_2 <= 16'sd0;
        end
        else begin
            out_valid <= (state == S_OUTPUT);

            if (state == S_OUTPUT) begin
                out_class_0 <= bias_round_sat(accum_reg[0], bias_rom[0]);
                out_class_1 <= bias_round_sat(accum_reg[1], bias_rom[1]);
                out_class_2 <= bias_round_sat(accum_reg[2], bias_rom[2]);
            end
        end
    end

endmodule
