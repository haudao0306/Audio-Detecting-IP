module classifier_layer1 #(
    parameter DATA_WIDTH        = 16,
    parameter IN_CHANNELS       = 64,
    parameter NUM_CYCLES        = 40,
    parameter ACCUM_WIDTH       = 48,
    parameter OUT_NODES         = 128,
    parameter BUS_WIDTH         = IN_CHANNELS * DATA_WIDTH,
    parameter OUT_BUS_WIDTH     = OUT_NODES * DATA_WIDTH,
    parameter CYCLE_IDX_WIDTH   = (NUM_CYCLES <= 2) ? 1 : $clog2(NUM_CYCLES),
    parameter NODE_IDX_WIDTH    = (OUT_NODES <= 2) ? 1 : $clog2(OUT_NODES),
    parameter WEIGHT_ADDR_WIDTH = (OUT_NODES * NUM_CYCLES <= 2) ? 1 : $clog2(OUT_NODES * NUM_CYCLES),

    parameter WEIGHT_FILE = "classifier.0_weight.hex",
    parameter BIAS_FILE   = "classifier.0_bias.hex"
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [BUS_WIDTH-1:0]         in_data_flat,

    input  wire                         out_ready,
    output wire                         out_valid,
    output wire [OUT_BUS_WIDTH-1:0]     out_layer_data
);

    (* rom_style = "block" *)
    reg [BUS_WIDTH-1:0]         weight_rom [0:(OUT_NODES*NUM_CYCLES)-1];
    reg signed [DATA_WIDTH-1:0] bias_rom   [0:OUT_NODES-1];

    initial begin
        $readmemh(WEIGHT_FILE, weight_rom);
        $readmemh(BIAS_FILE,   bias_rom);
    end

    wire                         buf_valid;
    wire [BUS_WIDTH-1:0]         buf_data;
    wire [CYCLE_IDX_WIDTH-1:0]   buf_cycle_idx;
    wire                         frame_ready;
    wire                         last_cycle;

    reg restart_replay;
    reg next_cycle_en;
    reg clear_frame;

    flatten_buffer #(
        .DATA_WIDTH      (DATA_WIDTH),
        .IN_CHANNELS     (IN_CHANNELS),
        .NUM_CYCLES      (NUM_CYCLES),
        .BUS_WIDTH       (BUS_WIDTH),
        .CYCLE_IDX_WIDTH (CYCLE_IDX_WIDTH)
    ) u_buffer (
        .clk             (clk),
        .rst_n           (rst_n),
        .in_valid        (in_valid),
        .in_ready        (in_ready),
        .in_data_flat    (in_data_flat),
        .restart_replay  (restart_replay),
        .next_cycle_en   (next_cycle_en),
        .clear_frame     (clear_frame),
        .out_valid       (buf_valid),
        .out_data_flat   (buf_data),
        .out_cycle_idx   (buf_cycle_idx),
        .frame_ready     (frame_ready),
        .last_cycle      (last_cycle)
    );

    localparam S_WAIT_FRAME = 3'd0;
    localparam S_START_NODE = 3'd1;
    localparam S_RUN_NODE   = 3'd2;
    localparam S_WAIT_NODE  = 3'd3;
    localparam S_SEND       = 3'd4;
    localparam S_CLEAR      = 3'd5;

    reg [2:0] state, next_state;
    reg [NODE_IDX_WIDTH-1:0] node_idx;
    reg [WEIGHT_ADDR_WIDTH-1:0] node_base_addr;
    reg [OUT_BUS_WIDTH-1:0] out_reg;

    wire dp_out_valid;
    wire node_is_last = (node_idx == OUT_NODES - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_WAIT_FRAME;
        else        state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            S_WAIT_FRAME: if (frame_ready)             next_state = S_START_NODE;
            S_START_NODE:                              next_state = S_RUN_NODE;
            S_RUN_NODE:   if (last_cycle && buf_valid) next_state = S_WAIT_NODE;
            S_WAIT_NODE:  if (dp_out_valid) begin
                              if (node_is_last)        next_state = S_SEND;
                              else                     next_state = S_START_NODE;
                          end
            S_SEND:       if (out_ready)               next_state = S_CLEAR;
            S_CLEAR:                                   next_state = S_WAIT_FRAME;
            default:                                   next_state = S_WAIT_FRAME;
        endcase
    end

    always @(*) begin
        restart_replay = 1'b0;
        next_cycle_en  = 1'b0;
        clear_frame    = 1'b0;
        case (state)
            S_START_NODE: restart_replay = 1'b1;
            S_RUN_NODE:   next_cycle_en  = buf_valid;
            S_CLEAR:      clear_frame    = 1'b1;
        endcase
    end

    wire [WEIGHT_ADDR_WIDTH-1:0] buf_cycle_addr =
        {{(WEIGHT_ADDR_WIDTH-CYCLE_IDX_WIDTH){1'b0}}, buf_cycle_idx};

    wire [WEIGHT_ADDR_WIDTH-1:0] weight_addr =
        node_base_addr + buf_cycle_addr;

    reg [BUS_WIDTH-1:0] weight_word_q;

    always @(posedge clk) begin
        weight_word_q <= weight_rom[weight_addr];
    end

    reg [BUS_WIDTH-1:0]         buf_data_q;
    reg [CYCLE_IDX_WIDTH-1:0]   cycle_idx_q;
    reg                         mac_en_q;
    reg signed [DATA_WIDTH-1:0] bias_q;

    wire mac_issue = (state == S_RUN_NODE) && buf_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buf_data_q  <= {BUS_WIDTH{1'b0}};
            cycle_idx_q <= {CYCLE_IDX_WIDTH{1'b0}};
            mac_en_q    <= 1'b0;
            bias_q      <= {DATA_WIDTH{1'b0}};
        end
        else begin
            mac_en_q    <= mac_issue;
            buf_data_q  <= buf_data;
            cycle_idx_q <= buf_cycle_idx;

            if (mac_issue)
                bias_q <= bias_rom[node_idx];
        end
    end

    wire signed [DATA_WIDTH-1:0] dp_out_data;

    linear1_datapath #(
        .DATA_WIDTH      (DATA_WIDTH),
        .CHANNELS        (IN_CHANNELS),
        .NUM_CYCLES      (NUM_CYCLES),
        .ACCUM_WIDTH     (ACCUM_WIDTH),
        .PIXEL_FRAC      (8),
        .WEIGHT_FRAC     (8),
        .OUT_FRAC        (8),
        .BUS_WIDTH       (BUS_WIDTH),
        .CYCLE_IDX_WIDTH (CYCLE_IDX_WIDTH)
    ) u_datapath (
        .clk             (clk),
        .rst_n           (rst_n),
        .in_valid        (mac_en_q),
        .in_cycle_idx    (cycle_idx_q),
        .in_data_flat    (buf_data_q),
        .in_weight_flat  (weight_word_q),
        .in_bias         (bias_q),
        .out_valid       (dp_out_valid),
        .out_node_data   (dp_out_data)
    );

    assign out_valid      = (state == S_SEND);
    assign out_layer_data = out_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            node_idx       <= {NODE_IDX_WIDTH{1'b0}};
            node_base_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
            out_reg        <= {OUT_BUS_WIDTH{1'b0}};
        end
        else begin
            if (state == S_WAIT_FRAME) begin
                node_idx       <= {NODE_IDX_WIDTH{1'b0}};
                node_base_addr <= {WEIGHT_ADDR_WIDTH{1'b0}};
                out_reg        <= {OUT_BUS_WIDTH{1'b0}};
            end

            if (state == S_WAIT_NODE && dp_out_valid) begin
                out_reg[node_idx * DATA_WIDTH +: DATA_WIDTH] <= dp_out_data;

                if (!node_is_last) begin
                    node_idx       <= node_idx + 1'b1;
                    node_base_addr <= node_base_addr + NUM_CYCLES;
                end
            end
        end
    end

endmodule
