// FPGA top level for testing with an ESP32: every byte received on rx is sent straight back on tx
module uart_echo_top
    import uart_pkg::*;
(
    input logic clk_i,
    input logic rst_i,
    input logic rx,  // Wire to the ESP32's TX pin
    output logic tx  // Wire to the ESP32's RX pin
);

    logic [DATA_BITS-1:0] rx_data;
    logic rx_valid;
    logic tx_ready;

    logic [DATA_BITS-1:0] pending_data;  // Last byte received, waiting to be sent back
    logic pending;  // High while pending_data hasn't been sent yet

    uart u_uart (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .tx_data(pending_data),
        .tx_valid(pending),
        .tx_ready(tx_ready),
        .tx(tx),
        .rx(rx),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        /* verilator lint_off PINCONNECTEMPTY */  // Errors aren't used for a simple echo test
        .rx_parity_error(),
        .rx_frame_error()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    always_ff @(posedge clk_i or posedge rst_i) begin  // Hold each received byte until tx takes it
        if (rst_i) begin
            pending_data <= '0;
            pending <= 0;
        end else begin
            if (pending && tx_ready) begin
                pending <= 0;
            end
            if (rx_valid) begin
                pending_data <= rx_data;
                pending <= 1;
            end
        end
    end
endmodule
