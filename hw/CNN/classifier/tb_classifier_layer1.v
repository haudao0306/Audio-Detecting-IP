`timescale 1ns / 1ps

module tb_classifier_layer1;

    // =====================================================
    // 1. PARAMETERS & ???NG D?N FILE
    // =====================================================
    parameter NUM_TESTS    = 10;  // C?n kh?p v?i bi?n NUM_TESTS trong c?u hình Python
    
    parameter DATA_WIDTH   = 16;
    parameter IN_CHANNELS  = 64;
    parameter NUM_CYCLES   = 40;
    parameter ACCUM_WIDTH  = 32;
    parameter Q_FRAC       = 8;
    parameter OUT_NODES    = 128;

    // T? ??ng tính toán t?ng s? l??ng m?u truy?n nh?n theo chu k? d?a trên s? l??ng tests
    localparam TOTAL_INPUTS  = NUM_CYCLES * NUM_TESTS; // T?ng s? dòng d? li?u ??u vào (Ví d?: 40 chu k? * 10 tests = 400 dòng)
    localparam TOTAL_OUTPUTS = NUM_TESTS;             // T?ng s? dòng k?t qu? mong ??i (M?i test xu?t ra 1 dòng k?t qu? 2048-bit)

    localparam IN_BUS_WIDTH  = IN_CHANNELS * DATA_WIDTH; // 1024-bit
    localparam OUT_BUS_WIDTH = OUT_NODES  * DATA_WIDTH; // 2048-bit

    // =====================================================
    // 2. TÍN HI?U K?T N?I DUT
    // =====================================================
    reg clk;
    reg rst_n;

    reg                        in_valid;
    wire                       in_ready;
    reg  [IN_BUS_WIDTH-1:0]    in_data_flat;

    reg                        out_ready;
    wire                       out_valid;
    wire [OUT_BUS_WIDTH-1:0]   out_layer_data;

    // M?ng b? nh? gi? l?p n?p d? li?u ki?m th? ???c sinh ra t? Python
    reg [IN_BUS_WIDTH-1:0]      input_memory    [0:TOTAL_INPUTS-1];
    reg [OUT_BUS_WIDTH-1:0]    expected_memory [0:TOTAL_OUTPUTS-1];

    // Các bi?n vòng l?p và ??m l?i t?ng quan
    integer i;
    integer sent_count;
    integer out_count;
    integer error_count;

    // Các b? ??m giám sát tín hi?u n?i b? (Debug Counters) ?? ki?m tra FSM
    integer dp_out_count;
    integer run_state_cycles;
    integer layer1_valid_count;

    // =====================================================
    // 3. DUT INSTANTIATION
    // =====================================================
    classifier_layer1 # (
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(IN_CHANNELS),
        .NUM_CYCLES(NUM_CYCLES),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .OUT_NODES(OUT_NODES)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready), 
        .in_data_flat(in_data_flat),

        .out_ready(out_ready), 
        .out_valid(out_valid),
        .out_layer_data(out_layer_data)
    );

    // =====================================================
    // 4. CLOCK GENERATOR (Chu k? 10ns -> 100MHz)
    // =====================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =====================================================
    // 5. INIT / LOAD FILES
    // =====================================================
    initial begin
        $display("");
        $display("====================================================");
        $display(" LOADING TEST VECTORS FOR CLASSIFIER_LAYER1");
        $display("====================================================");

        $readmemh("linear1_input.hex", input_memory);
        $readmemh("linear1_gold_output.hex", expected_memory);

        $display(" INPUT  VECTOR : linear1_input.hex");
        $display(" GOLDEN VECTOR : linear1_gold_output.hex");
        $display(" NUMBER OF TESTS: %0d frames", NUM_TESTS);
        $display(" TOTAL INPUTS  : %0d chu k? quét", TOTAL_INPUTS);
        $display(" TOTAL OUTPUTS : %0d kh?i k?t qu? (2048-bit)", TOTAL_OUTPUTS);
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // 6. INITIAL RESET STIMULUS
    // =====================================================
    initial begin
        rst_n        = 1'b0;
        in_valid     = 1'b0;
        in_data_flat = {IN_BUS_WIDTH{1'b0}};
        out_ready    = 1'b1; // S?n sàng nh?n d? li?u ??u ra t? t?ng phân l?p

        sent_count  = 0;
        out_count   = 0;
        error_count = 0;

        dp_out_count       = 0;
        run_state_cycles   = 0;
        layer1_valid_count = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
    end

    // =====================================================
    // 7. INPUT DRIVER WITH HANDSHAKE (H? tr? nhi?u Frame liên t?c)
    // =====================================================
    initial begin
        @(posedge rst_n);
        @(negedge clk);

        $display("");
        $display("====================================================");
        $display(" START SENDING INPUT STREAM TO CLASSIFIER_LAYER1");
        $display("====================================================");
        $display("");

        i = 0;

        // Vòng l?p n?p toàn b? lu?ng d? li?u c?a N test frames d?a trên c? ch? b?t tay in_ready
        while (i < TOTAL_INPUTS) begin
            @(negedge clk);

            in_valid     = 1'b1;
            in_data_flat = input_memory[i];

            @(posedge clk);

            if (in_ready) begin
                i = i + 1;
                sent_count = sent_count + 1;
            end
        end

        @(negedge clk);
        in_valid     = 1'b0;
        in_data_flat = {IN_BUS_WIDTH{1'b0}};

        $display("");
        $display("====================================================");
        $display(" INPUT STREAM FINISHED");
        $display(" SENT INPUTS : %0d / %0d chu k?", sent_count, TOTAL_INPUTS);
        $display(" WAITING FOR ALL OUT_VALID LINEAR RESPONSES");
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // 8. DEBUG COUNTERS (Giám sát ti?n ?? FSM n?i b? th?c t?)
    // =====================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // ??m s? chu k? Datapath tính toán xong m?t Node n?i b?
            if (uut.dp_out_valid)
                dp_out_count = dp_out_count + 1;

            // ??m s? chu k? FSM ho?t ??ng ? tr?ng thái RUN_NODE (S_RUN_NODE = 3'd2)
            if (uut.state == 3'd2) 
                run_state_cycles = run_state_cycles + 1;

            // ??m s? l??ng xung valid ??u ra th?c t? thu ???c
            if (out_valid)
                layer1_valid_count = layer1_valid_count + 1;
        end
    end

    // =====================================================
    // 9. AUTOMATIC OUTPUT CHECKER (So sánh ??ng t?ng Frame)
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && out_valid) begin

            // Tr??ng h?p phát hi?n ph?n c?ng xu?t th?a output v??t ng??ng c?u hình
            if (out_count >= TOTAL_OUTPUTS) begin
                $display("----------------------------------------------------");
                $display(" ERROR: EXTRA OUTPUT DETECTED FROM VERILOG");
                $display(" OUTPUT INDEX : %0d", out_count);
                $display(" VERILOG      : %h", out_layer_data);
                $display(" EXPECTED MAX : %0d outputs", TOTAL_OUTPUTS);
                $display("----------------------------------------------------");
                error_count = error_count + 1;
                finish_report();
            end

            $display("----------------------------------------------------");
            $display(" CHECKING OUTPUT FRAME INDEX : %0d", out_count);
            $display(" VERILOG DATA : %h", out_layer_data);
            $display(" PYTHON GOLDEN: %h", expected_memory[out_count]);

            // So sánh c?ng giá tr? bus ngõ ra v?i m?ng k?t qu? vàng t??ng ?ng
            if (out_layer_data !== expected_memory[out_count]) begin
                $display(" [!] RESULT MATCH STATUS: ---> MISMATCH <---");
                error_count = error_count + 1;
            end
            else begin
                $display(" [V] RESULT MATCH STATUS: ---> MATCH <---");
            end

            $display("----------------------------------------------------");
            $display("");

            out_count = out_count + 1;

            // Khi nh?n và ki?m tra ?? s? l??ng m?u ??u ra mong mu?n c?a toàn b? các tests
            if (out_count == TOTAL_OUTPUTS) begin
                repeat (10) @(posedge clk);
                finish_report();
            end
        end
    end

    // =====================================================
    // 10. SIMULATION REPORT TASK
    // =====================================================
    task finish_report;
    begin
        $display("");
        $display("====================================================");
        $display(" SIMULATION REPORT SUMMARY");
        $display("====================================================");
        $display(" TOTAL INPUT CYCLES SENT   : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" DATAPATH NODE DONE COUNT  : %0d (T?ng tích l?y)", dp_out_count);
        $display(" TOTAL FSM RUN_NODE CYCLES : %0d", run_state_cycles);
        $display(" CHECKED FRAMES COUNT      : %0d / %0d", out_count, TOTAL_OUTPUTS);
        $display(" CLASSIFIER VALID RAW COUNT: %0d", layer1_valid_count);
        $display(" TOTAL DETECTED MISMATCHES : %0d", error_count);

        if ((error_count == 0) && (out_count == TOTAL_OUTPUTS)) begin
            $display("");
            $display("  >>>> [PASS]: CLASSIFIER_LAYER1 IS 100% CORRECT VETTED! <<<<");
            $display("");
        end
        else begin
            $display("");
            $display("  >>>> [FAIL]: CLASSIFIER_LAYER1 HAS ERRORS OR LACKS OUTPUTS <<<<");
            $display("");
        end

        $display("====================================================");
        $display("");

        $finish;
    end
    endtask

    // =====================================================
    // 11. DYNAMIC TIMEOUT WATCHDOG
    // =====================================================
    initial begin
        // T? ??ng scale th?i gian timeout an toàn t? l? thu?n theo tham s? NUM_TESTS d? li?u ??u vào
        #(1000000 * NUM_TESTS);

        $display("");
        $display("====================================================");
        $display(" TIMEOUT ERROR TRIGGERED!");
        $display("====================================================");
        $display(" D? li?u không x? lý h?t trong th?i gian quy ??nh.");
        $display(" INPUT SENT                : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" DATAPATH NODE DONE COUNT  : %0d", dp_out_count);
        $display(" TOTAL S_RUN_NODE CYCLES   : %0d", run_state_cycles);
        $display(" CLASSIFIER OUTPUT COUNT   : %0d / %0d", out_count, TOTAL_OUTPUTS);
        $display(" CLASSIFIER VALID RAW COUNT: %0d", layer1_valid_count);
        $display(" TOTAL ERRORS              : %0d", error_count);
        $display("====================================================");
        $display("");

        $finish;
    end

endmodule