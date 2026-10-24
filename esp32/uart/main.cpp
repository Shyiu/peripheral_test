// Tests the FPGA's uart_echo_top. Wiring: ESP32 GPIO17 (TX2) -> FPGA rx, FPGA tx -> ESP32 GPIO16
// (RX2), and GND -> GND. On boot it runs a self-test, then forwards everything you type to the
// FPGA and prints whatever comes back. Press the ESP32's EN button to rerun the self-test.
#include <Arduino.h>

constexpr int FPGA_RX_PIN = 16;  // ESP32 pin that receives from the FPGA's tx
constexpr int FPGA_TX_PIN = 17;  // ESP32 pin that sends to the FPGA's rx
constexpr uint32_t BAUD = 115200;  // Must match BAUD_RATE in uart_pkg.sv
constexpr uint32_t TIMEOUT_MS = 20;  // One byte takes ~0.09 ms, so this is very generous

HardwareSerial &fpga = Serial2;

// Wait up to TIMEOUT_MS for a byte from the FPGA. Returns -1 if nothing arrives
int readByte() {
    uint32_t start = millis();
    while (!fpga.available()) {
        if (millis() - start > TIMEOUT_MS) {
            return -1;
        }
    }
    return fpga.read();
}

// Send every byte value one at a time and check each one comes back
int testEveryValue() {
    int errors = 0;
    for (int value = 0; value < 256; value++) {
        fpga.write(value);
        int echoed = readByte();
        if (echoed != value) {
            errors++;
            Serial.printf("  sent 0x%02X, got %s0x%02X\n", value, echoed < 0 ? "nothing " : "",
                          echoed < 0 ? 0 : echoed);
        }
    }
    return errors;
}

// Send a whole message back to back with no gaps, then check it all comes back in order
int testBurst() {
    const char message[] = "The quick brown fox jumps over the lazy dog 0123456789";
    const int length = sizeof(message) - 1;
    fpga.write(message, length);

    int errors = 0;
    for (int i = 0; i < length; i++) {
        int echoed = readByte();
        if (echoed != message[i]) {
            errors++;
        }
    }
    return errors;
}

void setup() {
    Serial.begin(BAUD);  // USB serial to your laptop
    fpga.begin(BAUD, SERIAL_8N1, FPGA_RX_PIN, FPGA_TX_PIN);
    delay(500);  // Give the serial monitor time to connect
    while (fpga.available()) {
        fpga.read();  // Throw away anything left over from before the test
    }

    Serial.println("\n=== FPGA UART echo test ===");
    int valueErrors = testEveryValue();
    Serial.printf("Every byte value: %s (%d/256 wrong)\n", valueErrors ? "FAIL" : "PASS", valueErrors);
    int burstErrors = testBurst();
    Serial.printf("Back-to-back burst: %s (%d wrong)\n", burstErrors ? "FAIL" : "PASS", burstErrors);
    Serial.println("Now type anything and the FPGA should echo it back:");
}

void loop() {
    while (Serial.available()) {
        fpga.write(Serial.read());  // Laptop -> FPGA
    }
    while (fpga.available()) {
        Serial.write(fpga.read());  // FPGA -> laptop
    }
}
