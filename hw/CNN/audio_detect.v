module audio_detect #(
    parameter LOG_MEL_OUT   = 16,
    parameter MEL_BINS      = 40,
    parameter MEL_IDX_WIDTH = 6,
    parameter FFT_SHIFT     = 6,

    parameter CNN_FIFO_DEPTH      = 32,
    parameter CNN_FIFO_ADDR_WIDTH = 5
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,

    // AUDIO INPUT
    input  wire [31:0]              audio_in_data,

    // CNN OUTPUT
    output wire                     cnn_out_valid,
    output wire signed [15:0]       cnn_class_0,
    output wire signed [15:0]       cnn_class_1,
    output wire signed [15:0]       cnn_class_2
);

    wire        fft_sync_internal;
    wire [43:0] fft_result;

    reg         fft_outputting;
    reg  [9:0]  fft_out_cnt;

    fftmain u_fft (
        .i_clk    (clk),
        .i_reset  (~rst_n),
        .i_ce     (enable),
        .i_sample (audio_in_data),
        .o_result (fft_result),
        .o_sync   (fft_sync_internal)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fft_outputting <= 1'b0;
            fft_out_cnt    <= 10'd0;
        end
        else if (enable) begin
            if (fft_sync_internal) begin
                fft_outputting <= 1'b1;
                fft_out_cnt    <= 10'd1;
            end
            else if (fft_outputting) begin
                if (fft_out_cnt == 10'd1023) begin
                    fft_outputting <= 1'b0;
                    fft_out_cnt    <= 10'd0;
                end
                else begin
                    fft_out_cnt <= fft_out_cnt + 1'b1;
                end
            end
        end
    end

    wire fft_out_valid = fft_sync_internal || fft_outputting;
    wire [9:0] fft_bin_idx = fft_sync_internal ? 10'd0 : fft_out_cnt;

    wire signed [21:0] fft_out_real = fft_result[43:22];
    wire signed [21:0] fft_out_imag = fft_result[21:0];

    wire signed [21:0] shifted_real =
        (fft_out_real + (22'sd1 << (FFT_SHIFT - 1))) >>> FFT_SHIFT;

    wire signed [21:0] shifted_imag =
        (fft_out_imag + (22'sd1 << (FFT_SHIFT - 1))) >>> FFT_SHIFT;

    wire signed [15:0] mel_in_real = shifted_real[15:0];
    wire signed [15:0] mel_in_imag = shifted_imag[15:0];

    wire datain_to_mel_valid =
        fft_out_valid && (fft_bin_idx < 10'd512);

    wire                     log_mel_valid_internal;
    wire [LOG_MEL_OUT-1:0]   log_mel_data_internal;
    wire [MEL_IDX_WIDTH-1:0] log_mel_idx_internal;

    log_mel_spectrogram #(
        .DATA_WIDTH    (16),
        .BIN_WIDTH     (9),
        .MEL_BINS      (MEL_BINS),
        .ACC_WIDTH     (57),
        .Q_SHIFT       (15),
        .LUT_BITS      (12),
        .OUT_WIDTH     (LOG_MEL_OUT),
        .MEL_IDX_WIDTH (MEL_IDX_WIDTH)
    ) u_log_mel (
        .clk             (clk),
        .reset_n         (rst_n),
        .enable          (enable),

        .datain_valid    (datain_to_mel_valid),
        .in_real         (mel_in_real),
        .in_imag         (mel_in_imag),
        .in_bin_idx      (fft_bin_idx[8:0]),

        .dataout_valid   (log_mel_valid_internal),
        .dataout         (log_mel_data_internal),
        .out_bin_idx     (log_mel_idx_internal)
    );

    wire                   fifo_in_ready;
    wire                   fifo_out_valid;
    wire                   fifo_out_ready;
    wire [LOG_MEL_OUT-1:0] fifo_out_data;

    stream_fifo #(
        .DATA_WIDTH(LOG_MEL_OUT),
        .DEPTH(CNN_FIFO_DEPTH),
        .ADDR_WIDTH(CNN_FIFO_ADDR_WIDTH)
    ) u_logmel_to_cnn_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(log_mel_valid_internal),
        .in_ready(fifo_in_ready),
        .in_data(log_mel_data_internal),

        .out_valid(fifo_out_valid),
        .out_ready(fifo_out_ready),
        .out_data(fifo_out_data)
    );

    reg logmel_fifo_overflow;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            logmel_fifo_overflow <= 1'b0;
        else if (log_mel_valid_internal && !fifo_in_ready)
            logmel_fifo_overflow <= 1'b1;
    end

    model_CNN #(
        .DATA_WIDTH  (LOG_MEL_OUT),
        .ACCUM_WIDTH (32),
        .OUT_CLASSES (3)
    ) u_model_CNN (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(fifo_out_valid),
        .in_ready(fifo_out_ready),
        .in_pixel(fifo_out_data),

        .out_valid(cnn_out_valid),
        .out_class_0(cnn_class_0),
        .out_class_1(cnn_class_1),
        .out_class_2(cnn_class_2)
    );

endmodule
