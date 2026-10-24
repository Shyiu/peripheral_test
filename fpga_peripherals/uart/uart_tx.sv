module uart_tx
    import uart_pkg::*;
(
    input logic clk_i,
    input logic rst_i,
    input logic [DATA_BITS-1:0] data_packet,  // Data to be sent
    input logic valid,  // Valid bit goes high when data_packet is ready to be sent
    output logic tx,  // Output Line
    output logic ready
);

    localparam int CYCLE_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam int COUNTER_WIDTH = $clog2(CYCLE_PER_BIT);
    localparam int DATA_COUNTER  = $clog2(DATA_BITS);
    localparam int STOP_COUNTER  = $clog2(STOP_BITS);

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY_BIT,
        STOP
    } state_t;

    state_t state;
    state_t next_state;

    logic [COUNTER_WIDTH-1:0] count;
    logic baud;

    assign baud = (count == COUNTER_WIDTH'(CYCLE_PER_BIT - 1));

    logic [DATA_BITS-1:0] stored_data;  // Stores data to transmit
    logic [DATA_COUNTER:0] data_state_counter;
    logic [STOP_COUNTER:0] stop_state_counter;
    logic parity_bit;

    // Values the registers above will take on the next clock edge
    logic [DATA_BITS-1:0] next_stored_data;
    logic [DATA_COUNTER:0] next_data_state_counter;
    logic [STOP_COUNTER:0] next_stop_state_counter;
    logic next_parity_bit;
    logic next_tx;
    logic next_ready;

    always_comb begin  // Next State Logic
        next_state = state;
        next_stored_data = stored_data;
        next_data_state_counter = data_state_counter;
        next_stop_state_counter = stop_state_counter;
        next_parity_bit = parity_bit;

        case (state)
            IDLE: begin  // When data paket is valid, start transactions
                next_stored_data = '0;
                next_data_state_counter = '0;
                next_stop_state_counter = '0;
                next_parity_bit = '0;
                if (valid && ready) begin  // Only accept a packet once we've told the sender we're ready
                    next_state = START;
                    next_stored_data = data_packet;
                    if (PARITY == EVEN) begin
                        next_parity_bit = ^data_packet;
                    end else if (PARITY == ODD) begin
                        next_parity_bit = 1 ^ (^data_packet);
                    end
                end
            end
            START: begin
                if (baud) begin
                    next_state = DATA;
                end
            end
            DATA: begin
                if (baud) begin
                    next_data_state_counter = data_state_counter + 1;
                    if (ENDNESS == LSB) begin
                        next_stored_data = {1'b0, stored_data[DATA_BITS-1:1]};
                    end else if (ENDNESS == MSB) begin
                        next_stored_data = {stored_data[DATA_BITS-2:0], 1'b0};
                    end
                    if (data_state_counter == (DATA_COUNTER + 1)'(DATA_BITS - 1)) begin
                        if (PARITY == NONE) begin // Skip Parity Stage if we've toggles parity bit to be off
                            next_state = STOP;
                        end else begin
                            next_state = PARITY_BIT;
                        end
                    end
                end
            end
            PARITY_BIT: begin
                if (baud) begin
                    next_state = STOP;
                end
            end
            STOP: begin
                if (baud) begin
                    next_stop_state_counter = stop_state_counter + 1;
                    if (stop_state_counter == (STOP_COUNTER + 1)'(STOP_BITS - 1)) begin
                        next_state = IDLE;
                    end
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_comb begin  // What tx + ready should be once the next values are loaded
        next_ready = 0;  // Busy in every state except IDLE
        case (next_state)
            IDLE: begin
                next_tx = 1;
                next_ready = 1;
            end
            START: next_tx = 0;
            DATA: begin
                if (ENDNESS == LSB) begin
                    next_tx = next_stored_data[0];
                end else begin
                    next_tx = next_stored_data[DATA_BITS-1];
                end
            end
            PARITY_BIT: next_tx = next_parity_bit;
            STOP: next_tx = 1;
            default: next_tx = 1;
        endcase
    end

    always_ff @(posedge clk_i or posedge rst_i) begin // Counter to create a baud tick dependent on clock cycle and baudrate
        if (rst_i) begin
            count <= '0;
        end else begin
            if (state == IDLE) begin
                count <= 0;
            end else begin
                count <= count + 1;
            end

            if (count == COUNTER_WIDTH'(CYCLE_PER_BIT - 1)) begin
                count <= 0;
            end
        end
    end

    always_ff @(posedge clk_i or posedge rst_i) begin  // Load every register with its next value
        if (rst_i) begin
            state <= IDLE;
            stored_data <= '0;
            data_state_counter <= '0;
            stop_state_counter <= '0;
            parity_bit <= '0;
            tx <= 1;  // Line idles high, so a reset doesn't look like a start bit
            ready <= 0;
        end else begin
            state <= next_state;
            stored_data <= next_stored_data;
            data_state_counter <= next_data_state_counter;
            stop_state_counter <= next_stop_state_counter;
            parity_bit <= next_parity_bit;
            tx <= next_tx;
            ready <= next_ready;
        end
    end
endmodule
