module power_unit #(
    parameter DATA_WIDTH = 16,
    parameter BIN_WIDTH  = 9   // ?? r?ng bit c?a index
)(
    input  wire                                 clk,
    input  wire                                 reset_n,
    input  wire                                 enable,
    // Ngõ vào 16-bit (?ã ???c c?t bit t? 22-bit c?a FFT)
    input  wire signed [DATA_WIDTH-1:0]         re_in,
    input  wire signed [DATA_WIDTH-1:0]         im_in,
    input  wire                                 valid_in,
    input  wire        [BIN_WIDTH-1:0]          bin_idx_in,     

    // Ngõ ra 33-bit (16*2 + 1 bit Carry)
    output reg         [2*DATA_WIDTH:0]         p_out,          
    output reg                                  valid_out,
    output reg         [BIN_WIDTH-1:0]          bin_idx_out
);

    // ============================================================
    // Stage 1: Bình ph??ng (Multiplier) -> Sinh ra 32-bit
    // ============================================================
    reg signed [2*DATA_WIDTH-1:0] re_sq;
    reg signed [2*DATA_WIDTH-1:0] im_sq;
    reg                           v_stage1;
    reg        [BIN_WIDTH-1:0]    bin_idx_stage1;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            re_sq              <= {(2*DATA_WIDTH){1'b0}};
            im_sq              <= {(2*DATA_WIDTH){1'b0}};
            v_stage1           <= 1'b0;
            bin_idx_stage1     <= {BIN_WIDTH{1'b0}};
        end else if (enable) begin
            // Ch? tính toán khi có d? li?u valid ?? ti?t ki?m n?ng l??ng ?óng c?t (Dynamic Power)
            if (valid_in) begin
                re_sq              <= re_in * re_in; // 16-bit * 16-bit = 32-bit
                im_sq              <= im_in * im_in; // 16-bit * 16-bit = 32-bit
                v_stage1           <= 1'b1;
                bin_idx_stage1     <= bin_idx_in;
            end else begin
                v_stage1           <= 1'b0;
                // Không c?n reset data (re_sq, im_sq) v? 0 khi valid_in th?p 
                // Gi? nguyên tr?ng thái c? giúp gi?m Flip-Flop toggling (gi?m hao pin)
            end
        end
    end

    // ============================================================
    // Stage 2: C?ng hai bình ph??ng (Adder) -> Sinh ra 33-bit
    // ============================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            p_out           <= {(2*DATA_WIDTH+1){1'b0}};
            valid_out       <= 1'b0;
            bin_idx_out     <= {BIN_WIDTH{1'b0}};
        end else if (enable) begin
            if (v_stage1) begin
                // Ép ki?u Unsigned và thêm 1 bit 0 ? MSB ?? c?ng an toàn thành 33-bit
                p_out           <= $unsigned({1'b0, re_sq}) + $unsigned({1'b0, im_sq});
                valid_out       <= 1'b1;
                bin_idx_out     <= bin_idx_stage1;
            end else begin
                valid_out       <= 1'b0;  
                // T??ng t?, gi? nguyên tr?ng thái p_out ?? ti?t ki?m n?ng l??ng
            end
        end
    end
endmodule