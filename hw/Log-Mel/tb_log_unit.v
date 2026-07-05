`timescale 1ns / 1ps

module tb_log_unit;

    // ============================================================
    // 1. Khai báo các Parameter (Kh?p 100% v?i module chính)
    // ============================================================
    localparam IN_WIDTH   = 57;
    localparam Q_SHIFT    = 15;
    localparam E_WIDTH    = 42;
    localparam LUT_BITS   = 12;
    localparam LUT_SIZE   = 4096;
    localparam OUT_WIDTH  = 16;
    localparam FRAC_BITS  = 12;
    localparam IDX_WIDTH  = 6;
    localparam NUM_TESTS  = 200; // S? l??ng m?u test kh?p v?i file Python

    // ============================================================
    // 2. Các tín hi?u k?t n?i v?i DUT (Device Under Test)
    // ============================================================
    reg                   clk;
    reg                   reset_n;
    reg                   enable;
    reg                   valid_in;
    reg  [IN_WIDTH-1:0]   log_in;
    reg  [IDX_WIDTH-1:0]  idx_in;

    wire [OUT_WIDTH-1:0]  log_out;
    wire                  valid_out;
    wire [IDX_WIDTH-1:0]  idx_out;

    // ============================================================
    // 3. Kh?i t?o m?ng b? nh? ch?a d? li?u Stimulus và Expected
    // ============================================================
    // [63:57] = idx_in, [56:0] = log_in (Nâng lên 64 bit ?? kh?p 16 ký t? Hex)
    reg [63:0] stim_mem [0:NUM_TESTS-1];  
    
    // [23:16] = idx_out, [15:0] = log_out (Nâng lên 24 bit ?? kh?p 6 ký t? Hex)
    reg [23:0] exp_mem  [0:NUM_TESTS-1]; 

    // Các bi?n ??m ?i?u khi?n
    integer in_ptr  = 0;
    integer out_ptr = 0;
    integer errors  = 0;

    // ============================================================
    // 4. K?t n?i th?c th? v?i Module DUT
    // ============================================================
    log_unit #(
        .IN_WIDTH(IN_WIDTH),
        .Q_SHIFT(Q_SHIFT),
        .E_WIDTH(E_WIDTH),
        .LUT_BITS(LUT_BITS),
        .LUT_SIZE(LUT_SIZE),
        .OUT_WIDTH(OUT_WIDTH),
        .FRAC_BITS(FRAC_BITS),
        .IDX_WIDTH(IDX_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .valid_in(valid_in),
        .log_in(log_in),
        .idx_in(idx_in),
        .log_out(log_out),
        .valid_out(valid_out),
        .idx_out(idx_out)
    );

    // ============================================================
    // 5. B? sinh xung Clock (Chu k? 10ns -> T?n s? 100MHz)
    // ============================================================
    always #5 clk = ~clk;

    // ============================================================
    // 6. Kh?i n?p d? li?u t? file (.mem) vào b? nh? Testbench
    // ============================================================
    initial begin
        $readmemh("log_in_stimulus.mem", stim_mem);
        $readmemh("log_out_expected.mem", exp_mem);
    end

    // ============================================================
    // 7. Kh?i x? lý kích hoàn (B?m d? li?u ngõ vào)
    // ============================================================
    initial begin
        // Kh?i t?o tr?ng thái ban ??u
        clk      = 0;
        reset_n  = 0;
        enable   = 0;
        valid_in = 0;
        log_in   = 0;
        idx_in   = 0;

        // Reset h? th?ng trong 4 chu k? clock
        #40;
        reset_n  = 1;
        enable   = 1;
        #10;

        $display("\n========================================================================");
        $display("==            B?T ??U KI?M TRA T? ??NG KH?I LOG_UNIT                  ==");
        $display("========================================================================\n");

        // Vòng l?p b?m toàn b? các m?u test t? file kích ho?t
        for (in_ptr = 0; in_ptr < NUM_TESTS; in_ptr = in_ptr + 1) begin
            @(posedge clk);
            // Gi?i nén d? li?u t? stim_mem ?? ??a vào chân n?p c?a DUT
            idx_in   <= stim_mem[in_ptr][62:57];
            log_in   <= stim_mem[in_ptr][56:0];
            valid_in <= 1'b1;

            // Dùng %016h ?? in nguyên d?i 64-bit Hex y h?t trong file .mem, và %015h cho 57-bit log_in
            $display("[INPUT  @Time %0d ns] G?i M?u %0d -> D? li?u G?c = %016h | Idx = %0d, Log_in = %015h", 
                     $time, in_ptr, stim_mem[in_ptr], stim_mem[in_ptr][62:57], stim_mem[in_ptr][56:0]);
        end

        // Sau khi b?m h?t d? li?u, h? c? valid_in
        @(posedge clk);
        valid_in <= 1'b0;
        log_in   <= 0;
        idx_in   <= 0;
    end

    // ============================================================
    // 8. Kh?i giám sát và t? ??ng so sánh ngõ ra (Checker)
    // ============================================================
    reg [IDX_WIDTH-1:0] exp_idx;
    reg [OUT_WIDTH-1:0] exp_log;
    wire [23:0]         hw_full_out; // Bi?n n?i 24-bit ?? in ra ng?m cho d?

    assign hw_full_out = {2'b00, idx_out, log_out}; // Ghép ngõ ra ph?n c?ng l?i thành form 24-bit

    always @(posedge clk) begin
        // N?u m?ch báo có d? li?u ngõ ra h?p l? (valid_out = 1)
        if (enable && valid_out) begin
            // Trích xu?t giá tr? k?t qu? mong ??i t? mô hình Python
            exp_idx = exp_mem[out_ptr][21:16];
            exp_log = exp_mem[out_ptr][15:0];

            $display("------------------------------------------------------------------------");
            $display("[OUTPUT @Time %0d ns] Ki?m tra m?u ngõ ra th?: %0d", $time, out_ptr);
            
            // Dùng %06h cho 24-bit (6 ký t?) và %04h cho 16-bit (4 ký t?)
            $display("   -> VERILOG Hardware: Chu?i ghép (Hex) = %06h | Idx_out = %0d, Log_out = %04h", 
                     hw_full_out, idx_out, log_out);
            $display("   -> PYTHON Golden:    Chu?i ghép (Hex) = %06h | Idx_exp = %0d, Log_exp = %04h", 
                     exp_mem[out_ptr], exp_idx, exp_log);

            // Ti?n hành so sánh ??i chi?u t? ??ng gi?a 2 bên
            if ((idx_out !== exp_idx) || (log_out !== exp_log)) begin
                $display("   [=> L?I SAI KH?P!!!] K?t qu? ph?n c?ng và mô hình không trùng nhau.");
                errors = errors + 1;
            end else begin
                $display("   [=> CHU?N XÁC]");
            end
            $display("------------------------------------------------------------------------");

            // T?ng con tr? qu?n lý m?u ngõ ra
            out_ptr = out_ptr + 1;

            // N?u ?ã thu th?p và so sánh ?? toàn b? s? l??ng m?u test
            if (out_ptr == NUM_TESTS) begin
                $display("\n========================================================================");
                $display("==                     K?T LU?N KI?M TRA PH?N C?NG                    ==");
                $display("========================================================================");
                if (errors == 0) begin
                    $display("  >>>> K?T QU?: [ SUCCESS - PASS ] <<<<");
                    $display("  Chúc m?ng! Toàn b? %0d m?u ki?m tra trùng kh?p hoàn toàn v?i Python!", NUM_TESTS);
                end else begin
                    $display("  >>>> K?T QU?: [ FAILURE - FAIL ] <<<<");
                    $display("  Phát hi?n th?y có %0d m?u b? sai l?ch giá tr?. C?n rà soát l?i logic m?ch!", errors);
                end
                $display("========================================================================\n");
                $finish; // K?t thúc phiên mô ph?ng
            end
        end
    end

endmodule