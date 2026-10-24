module uart_rx
    import uart_pkg::*;
(
    input logic clk_i,
    input logic rst_i,
    input logic rx,  // Input Line
    output logic [DATA_BITS-1:0] data_packet,  // Received data, held until the next packet arrives
    output logic valid,  // Pulses high for one cycle when data_packet has a new packet
    output logic parity_error,  // Parity bit didn't match the data
    output logic frame_error  // A stop bit was low
);

    localparam int CYCLE_PER_BIT = CLK_HZ / BAUD_RATE;
    localparam int HALF_BIT = CYCLE_PER_BIT / 2;
    localparam int VOTE_GAP = (SAMPLE_VOTE == 3) ? CYCLE_PER_BIT / 8 : 0;  // Cycles between votes
    localparam int COUNTER_WIDTH = $clog2(CYCLE_PER_BIT);
    localparam int DATA_COUNTER = $clog2(DATA_BITS);
    localparam int STOP_COUNTER = $clog2(STOP_BITS);

    typedef enum logic [2:0] {
        IDLE,
        START,
        DATA,
        PARITY_BIT,
        STOP
    } state_t;

    state_t state;
    state_t next_state;

    // rx comes from outside our clock domain, so pass it through 2 flops before using it
    logic rx_meta;
    logic rx_sync;
    logic rx_prev;  // rx_sync one cycle ago, to spot the high -> low edge of a start bit

    logic [COUNTER_WIDTH-1:0] count;
    logic [COUNTER_WIDTH-1:0] period_end;
    logic sample;

    // Votes are taken at middle - VOTE_GAP, middle, and middle + VOTE_GAP. The bit is decided at
    // the last vote, so START waits half a bit plus one gap, then every full bit after that lands
    // on the last vote of the next bit
    assign period_end = (state == START) ? COUNTER_WIDTH'(HALF_BIT + VOTE_GAP - 1)
                                         : COUNTER_WIDTH'(CYCLE_PER_BIT - 1);
    assign sample = (count == period_end);

    logic vote_early;  // rx_sync at middle - VOTE_GAP
    logic vote_mid;  // rx_sync at middle
    logic majority;  // High when at least 2 of the 3 votes are high
    logic rx_bit;  // The value of the current bit, used by every state except IDLE

    assign majority = (vote_early & vote_mid) | (vote_mid & rx_sync) | (vote_early & rx_sync);
    assign rx_bit   = (SAMPLE_VOTE == 3) ? majority : rx_sync;

    logic [DATA_BITS-1:0] stored_data;  // Stores data as it's received
    logic [DATA_COUNTER:0] data_state_counter;
    logic [STOP_COUNTER:0] stop_state_counter;

    // Values the registers above will take on the next clock edge
    logic [DATA_BITS-1:0] next_stored_data;
    logic [DATA_COUNTER:0] next_data_state_counter;
    logic [STOP_COUNTER:0] next_stop_state_counter;
    logic next_valid;
    logic next_parity_error;
    logic next_frame_error;

    assign data_packet = stored_data;

    always_comb begin  // Next State Logic
        next_state = state;
        next_stored_data = stored_data;
        next_data_state_counter = data_state_counter;
        next_stop_state_counter = stop_state_counter;
        next_valid = 0;  // Only high for the one cycle a packet finishes
        next_parity_error = parity_error;
        next_frame_error = frame_error;

        case (state)
            IDLE: begin  // Falling edge on the line is the start of a start bit
                next_data_state_counter = '0;
                next_stop_state_counter = '0;
                // Wait for an edge, not just a low line, so a line that's still low after a bad
                // stop bit isn't mistaken for a new start bit
                if (rx_prev && !rx_sync) begin
                    next_state = START;
                    next_parity_error = 0;
                    next_frame_error = 0;
                end
            end
            START: begin
                if (sample) begin
                    if (!rx_bit) begin
                        next_state = DATA;
                    end else begin  // Line went back high, so it was a glitch and not a start bit
                        next_state = IDLE;
                    end
                end
            end
            DATA: begin
                if (sample) begin
                    next_data_state_counter = data_state_counter + 1;
                    if (ENDNESS == LSB) begin
                        next_stored_data = {rx_bit, stored_data[DATA_BITS-1:1]};
                    end else if (ENDNESS == MSB) begin
                        next_stored_data = {stored_data[DATA_BITS-2:0], rx_bit};
                    end
                    if (data_state_counter == (DATA_COUNTER + 1)'(DATA_BITS - 1)) begin
                        if (PARITY == NONE) begin
                            next_state = STOP;
                        end else begin
                            next_state = PARITY_BIT;
                        end
                    end
                end
            end
            PARITY_BIT: begin
                if (sample) begin
                    if (PARITY == EVEN) begin
                        next_parity_error = rx_bit != ^stored_data;
                    end else if (PARITY == ODD) begin
                        next_parity_error = rx_bit != (1 ^ (^stored_data));
                    end
                    next_state = STOP;
                end
            end
            STOP: begin
                if (sample) begin
                    next_stop_state_counter = stop_state_counter + 1;
                    if (!rx_bit) begin
                        next_frame_error = 1;
                    end
                    // Leave in the middle of the last stop bit, so we're already watching for the
                    // next start bit
                    if (stop_state_counter == (STOP_COUNTER + 1)'(STOP_BITS - 1)) begin
                        next_state = IDLE;
                        next_valid = 1;
                    end
                end
            end
            default: next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk_i or posedge rst_i) begin  // Synchronizer for rx
        if (rst_i) begin
            rx_meta <= 1;  // Line idles high, so a reset doesn't look like a start bit
            rx_sync <= 1;
            rx_prev <= 1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
            rx_prev <= rx_sync;
        end
    end

    always_ff @(posedge clk_i or posedge rst_i) begin // Counter to create a sample tick in the middle of each bit
        if (rst_i) begin
            count <= '0;
        end else begin
            if (state == IDLE) begin
                count <= 0;
            end else begin
                count <= count + 1;
            end

            if (sample) begin
                count <= 0;
            end
        end
    end

    always_ff @(posedge clk_i or posedge rst_i) begin  // Capture the 2 votes before the last one
        if (rst_i) begin
            vote_early <= 1;
            vote_mid   <= 1;
        end else begin
            if (count == period_end - COUNTER_WIDTH'(2 * VOTE_GAP)) begin
                vote_early <= rx_sync;
            end
            if (count == period_end - COUNTER_WIDTH'(VOTE_GAP)) begin
                vote_mid <= rx_sync;
            end
        end
    end

    always_ff @(posedge clk_i or posedge rst_i) begin  // Load every register with its next value
        if (rst_i) begin
            state <= IDLE;
            stored_data <= '0;
            data_state_counter <= '0;
            stop_state_counter <= '0;
            valid <= 0;
            parity_error <= 0;
            frame_error <= 0;
        end else begin
            state <= next_state;
            stored_data <= next_stored_data;
            data_state_counter <= next_data_state_counter;
            stop_state_counter <= next_stop_state_counter;
            valid <= next_valid;
            parity_error <= next_parity_error;
            frame_error <= next_frame_error;
        end
    end
endmodule
