`timescale 1ns / 1ps

module tb_flatten_buffer;

    // ==========================================
    // 1. KHAI BÁO PARAMETER
    // ==========================================
    parameter DATA_WIDTH  = 16;
    parameter IN_CHANNELS = 64;
    parameter NUM_CYCLES  = 40;
    localparam BUS_WIDTH  = IN_CHANNELS * DATA_WIDTH; // 1024-bit

    // ==========================================
    // 2. KHAI BÁO TÍN HI?U
    // ==========================================
    reg                  clk;
    reg                  rst_n;
    
    // Tín hi?u Input (Mô ph?ng Features Layer 3)
    reg                  in_valid;
    reg  [BUS_WIDTH-1:0] in_data_flat;
    
    // Tín hi?u Output (N?i sang Datapath Layer 1)
    wire                 out_valid;
    wire [BUS_WIDTH-1:0] out_data_flat;
    wire                 out_pass;
    wire [5:0]           out_cycle_idx;

    integer i;
    integer pass1_count = 0;
    integer pass2_count = 0;

    // ==========================================
    // 3. KH?I T?O MODULE C?N TEST (DUT)
    // ==========================================
    flatten_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(IN_CHANNELS),
        .NUM_CYCLES(NUM_CYCLES)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data_flat(in_data_flat),
        .out_valid(out_valid),
        .out_data_flat(out_data_flat),
        .out_pass(out_pass),
        .out_cycle_idx(out_cycle_idx)
    );

    // ==========================================
    // 4. T?O XUNG CLOCK (100MHz)
    // ==========================================
    always #5 clk = ~clk;

    // ==========================================
    // 5. K?CH B?N MÔ PH?NG (STIMULUS)
    // ==========================================
    initial begin
        // Kh?i t?o tr?ng thái ban ??u
        clk = 0;
        rst_n = 0;
        in_valid = 0;
        in_data_flat = 0;

        $display("==========================================================");
        $display("[TB] BAT DAU MO PHONG FLATTEN BUFFER OVERLAP");
        $display("==========================================================");

        // Reset h? th?ng
        #20;
        rst_n = 1;
        #15;

        // ----------------------------------------------------
        // K?CH B?N: B?M 40 NH?P D? LI?U T? LAYER 3
        // ----------------------------------------------------
        $display("[TB] => Kich hoat in_valid. Bom 40 pixel (Layer 3 xua't)...");
        for (i = 0; i < NUM_CYCLES; i = i + 1) begin
            @(posedge clk);
            in_valid <= 1'b1;
            // N?p giá tr? i vào T?T C? 64 kênh (?? d? ??i chi?u)
            // Cú pháp {64{16-bit}} s? nhân b?n giá tr? i lên 64 l?n thành bus 1024-bit
            in_data_flat <= { IN_CHANNELS { i[15:0] } };
        end

        // ----------------------------------------------------
        // NG?T D? LI?U - M?CH PH?I T? CHUY?N SANG PASS 2
        // ----------------------------------------------------
        @(posedge clk);
        in_valid <= 1'b0;      // T?t valid vào
        in_data_flat <= 1024'd0;
        
        $display("[TB] => Da bom xong 40 nhip. Ngat in_valid!");
        $display("[TB] => Cho mach tu dong Phat lai (Playback) Pass 2...");

        // Ch? thêm 50 chu k? n?a ?? quan sát Pass 2 ch?y xong r?i v? IDLE
        #500;
        
        $display("==========================================================");
        $display("  TONG KET KET QUA KHOI BUFFER");
        $display("  - So nhip xuat Pass 1: %0d / 40", pass1_count);
        $display("  - So nhip xuat Pass 2: %0d / 40", pass2_count);
        if (pass1_count == 40 && pass2_count == 40)
            $display("  => PASSED! Mach hoat dong xuat sac 100%.");
        else
            $display("  => FAILED! Kiem tra lai logic FSM.");
        $display("==========================================================");
        $finish;
    end

    // ==========================================
    // 6. KH?I THEO DÕI K?T QU? ??U RA (MONITOR)
    // ==========================================
    always @(posedge clk) begin
        if (out_valid) begin
            // In k?t qu? ra màn hình (Ch? l?y 16-bit th?p nh?t ??i di?n cho 1 kênh ?? d? nhìn)
            $display($time, " ns | PASS = %b | CYCLE = %02d | DATA_OUT = %0d", 
                     out_pass, out_cycle_idx, out_data_flat[15:0]);
            
            // ??m s? l??ng nh?p ?? t?ng k?t
            if (out_pass == 1'b0) begin
                pass1_count = pass1_count + 1;
            end else begin
                pass2_count = pass2_count + 1;
            end
            
            // T? ??ng ki?m tra l?i (Auto Check)
            // Giá tr? DATA xu?t ra ph?i luôn b?ng ?úng Cycle Index hi?n t?i
            if (out_data_flat[15:0] !== {10'd0, out_cycle_idx}) begin
                $display("   -> [ERROR] Du lieu sai lech! Expected: %0d, Got: %0d", out_cycle_idx, out_data_flat[15:0]);
            end
        end
    end

endmodule