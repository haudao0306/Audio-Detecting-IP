// ============================================================
//  log_mel_spectrogram.v
//  Top module - Ki?n trúc Self-Contained Latency
// ============================================================

module log_mel_spectrogram #(
    // Parameters
    parameter DATA_WIDTH    = 16,  
    parameter BIN_WIDTH     = 9,   // ?? r?ng Index t? FFT (512 bins)
    parameter MEL_BINS      = 40,  
    parameter ACC_WIDTH     = 57,  
    parameter Q_SHIFT       = 15,
    parameter LUT_BITS      = 12,
    parameter OUT_WIDTH     = 16,
    parameter MEL_IDX_WIDTH = 6    // ?? r?ng Index ngõ ra (40 Mel bins)
)(
    input  wire                                 clk,
    input  wire                                 reset_n,
    input  wire                                 enable,
    // --------------------------------------------------------
    // Ngõ vào t? kh?i FFT
    // --------------------------------------------------------
    input  wire                                 datain_valid,
    input  wire signed [DATA_WIDTH-1:0]         in_real,
    input  wire signed [DATA_WIDTH-1:0]         in_imag,
    input  wire        [BIN_WIDTH-1:0]          in_bin_idx, // Index g?c t? FFT

    // --------------------------------------------------------
    // Ngõ ra Log-Mel
    // --------------------------------------------------------
    output wire                                 dataout_valid,
    output wire        [OUT_WIDTH-1:0]          dataout,
    output wire     [MEL_IDX_WIDTH-1:0]         out_bin_idx // Index t??ng ?ng v?i d? li?u ngõ ra
);

    // ============================================================
    // ???NG DÂY K?T N?I N?I B? (INTERNAL WIRES)
    // ============================================================
    
    // Gi?a Power Unit và MAC Unit
    wire                 pwr_valid;
    wire [2*DATA_WIDTH:0] pwr_data; 
    wire [BIN_WIDTH-1:0]  pwr_bin_idx; 
    
    // Gi?a MAC Unit và Log Unit
    wire                 mac_valid;
    wire [ACC_WIDTH-1:0] mac_data;
    wire [MEL_IDX_WIDTH-1:0] mac_mel_idx;

    // ============================================================
    // 1. INSTANTIATION: Power Unit
    // ============================================================
    power_unit #(
        .DATA_WIDTH(DATA_WIDTH),
        .BIN_WIDTH(BIN_WIDTH)
    ) u_power_unit (
        .clk             (clk),
        .reset_n         (reset_n),
        .enable          (enable),
        
        .valid_in        (datain_valid),
        .re_in           (in_real),
        .im_in           (in_imag),
        .bin_idx_in      (in_bin_idx),
        
        .valid_out       (pwr_valid),
        .p_out           (pwr_data),
        .bin_idx_out     (pwr_bin_idx)
    );

    // ============================================================
    // 2. INSTANTIATION: MAC Unit
    // ============================================================
    mac_unit #(
        .NUM_FILTERS(MEL_BINS),
        .NUM_BINS(1 << BIN_WIDTH),
        .PK_WIDTH(2*DATA_WIDTH + 1),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_mac_unit (
        .clk             (clk),
        .reset_n         (reset_n),
        .enable          (enable),
        
        .valid_in        (pwr_valid),
        .mel_in          (pwr_data),
        .bin_idx         (pwr_bin_idx), 
        
        .valid_out       (mac_valid),
        .mel_out         (mac_data),
        .mel_idx         (mac_mel_idx)
    );

    // ============================================================
    // 3. INSTANTIATION: Log Unit
    // ============================================================
    log_unit #(
        .IN_WIDTH(ACC_WIDTH),
        .Q_SHIFT(Q_SHIFT),
        .E_WIDTH(ACC_WIDTH - Q_SHIFT),
        .LUT_BITS(LUT_BITS),
        .LUT_SIZE(1 << LUT_BITS),
        .OUT_WIDTH(OUT_WIDTH),
        .IDX_WIDTH(MEL_IDX_WIDTH)
    ) u_log_unit (
        .clk             (clk),
        .reset_n         (reset_n),
        .enable          (enable),
        
        .valid_in        (mac_valid),
        .log_in          (mac_data),
        .idx_in          (mac_mel_idx),
        
        .valid_out       (dataout_valid),
        .log_out         (dataout),
        .idx_out         (out_bin_idx)
    );

endmodule