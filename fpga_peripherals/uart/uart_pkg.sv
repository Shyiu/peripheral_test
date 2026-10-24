package uart_pkg;
    typedef enum int {
        NONE,
        ODD,
        EVEN
    } parity_t;

    typedef enum logic {
        LSB,
        MSB
    } data_end;

    parameter int CLK_HZ = 50_000_000;
    parameter int BAUD_RATE = 115200;
    parameter int DATA_BITS = 8;  // Number from 5-9
    parameter int STOP_BITS = 1;  // Number from 1-2
    parameter int SAMPLE_VOTE = 3;  // RX samples per bit: 1 (middle only) or 3 (majority vote)
    parameter parity_t PARITY = NONE;  // Type of NONE, ODD, or EVEN
    parameter data_end ENDNESS = LSB;  // Send LSB or MSB of data first
endpackage
