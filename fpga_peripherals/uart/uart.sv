module uart
    import uart_pkg::*;
(
    input logic clk_i,
    input logic rst_i,

    // Transmit side
    input logic [DATA_BITS-1:0] tx_data,  // Data to be sent
    input logic tx_valid,  // High when tx_data is ready to be sent
    output logic tx_ready,  // High when the transmitter can accept tx_data
    output logic tx,  // Output Line

    // Receive side
    input logic rx,  // Input Line
    output logic [DATA_BITS-1:0] rx_data,  // Received data, held until the next packet arrives
    output logic rx_valid,  // Pulses high for one cycle when rx_data has a new packet
    output logic rx_parity_error,  // Parity bit didn't match the data
    output logic rx_frame_error  // A stop bit was low
);

    uart_tx u_tx (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .data_packet(tx_data),
        .valid(tx_valid),
        .tx(tx),
        .ready(tx_ready)
    );

    uart_rx u_rx (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .rx(rx),
        .data_packet(rx_data),
        .valid(rx_valid),
        .parity_error(rx_parity_error),
        .frame_error(rx_frame_error)
    );
endmodule
