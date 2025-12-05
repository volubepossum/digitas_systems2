// -----------------------------------------------------------------------------
//
//  Title      :  Top level for task 2 of the Edge-Detection design project.
//             :
//  Developers :  Otto Westy Rasmussen - s203838@dtu.dk
//             :
//  Purpose    :  A top-level entity connecting all the components.
//             :
//  Revision   :  02203 fall 2025 v.1.0
//
// -----------------------------------------------------------------------------

module top (
    input  logic clk_100mhz,
    input  logic rst,
    output logic led,
    input  logic start,
    input  logic serial_tx,   // from the PC
    output logic serial_rx,   // to the PC
    output logic rst_led
);
    // Parameters
    // Clock: the clock will be 100MHz *  CLK_MULTIPLY_FACTOR / CLK_DIVISION_FACTOR.
    localparam int CLK_MULTIPLY_FACTOR = 8; // 2 - 16: 1.6 GHz physical limitation on feedback clock
    localparam int CLK_DIVISION_FACTOR = 4; // 1 - 128

    localparam int WIDTH  = 352;
    localparam int HEIGHT = 288;

    // Internal signals
    logic clk;

    logic mem_ena, mem_wea;
    logic [15:0] mem_addra;
    logic [31:0] mem_doa, mem_dia;

    logic mem_enb, mem_web;
    logic [15:0] mem_addrb;
    logic [31:0] mem_dib, mem_dob;

    logic en, we, finish, start_db;
    logic [31:0] dataRa, dataRb, dataRc, dataW;

    logic row_cached;

    logic [7:0] data_stream_in, data_stream_out;
    logic data_stream_in_stb, data_stream_in_ack, data_stream_out_stb;

    logic tx, rx;

    assign tx = serial_tx;
    assign serial_rx = rx;
    // LED output
    assign led = finish;

    localparam int RST_DURATION = 5;
    logic [RST_DURATION-1:0] rst_buff;
    logic rst_held;
    always_ff @( posedge clk or posedge rst ) begin 
        if (rst) rst_buff[RST_DURATION-1] <= 1'b1;
        else     rst_buff[RST_DURATION-1] <= 1'b0;
    end
             
    genvar i;
    generate
        for (i = 0; i < RST_DURATION - 1; i = i + 1) begin
            always_ff @( posedge clk or posedge rst ) begin
                if (rst) rst_buff[i] <= 1'b1; 
                else     rst_buff[i] <= rst_buff[i+1];
            end
        end
    endgenerate

    assign rst_held = rst_buff[0];
    assign rst_led = rst_held;

    // Clock divider instance
    clock_divider #(
        .DIVIDE(CLK_DIVISION_FACTOR), 
        .MULTIPLY(CLK_MULTIPLY_FACTOR)
    ) clock_divider_inst_0 (
        .clk_in(clk_100mhz),
        .clk_out(clk)
    );

    // Debounce instance
    debounce debounce_inst_0 (
        .clk(clk),
        .reset(rst_held),
        .sw(start),
        .db_level(start_db),
        .db_tick()
    );

    // Accelerator instance
    acc # (.WIDTH(WIDTH), .HEIGHT(HEIGHT)) accelerator_inst_0 (
        .clk(clk),
        .rst(rst_held),
        .dataRa(dataRa),
        .dataRb(dataRb),
        .dataRc(dataRc),
        .dataW(dataW),
        .en(en),
        .we(we),
        .row_cached(row_cached),
        .start(start_db),
        .finish(finish)
    );

    // Controller instance
    controller controller_inst_0 (
        .clk(clk),
        .reset(rst_held),
        .data_stream_tx(data_stream_in),
        .data_stream_tx_stb(data_stream_in_stb),
        .data_stream_tx_ack(data_stream_in_ack),
        .data_stream_rx(data_stream_out),
        .data_stream_rx_stb(data_stream_out_stb),
        .mem_en(mem_enb),
        .mem_we(mem_web),
        .mem_addr(mem_addrb),
        .mem_dw(mem_dib),
        .mem_dr(mem_dob)
    );

    // UART instance
    uart # (
        .P_BAUD_RATE(115200),
        .P_CLOCK_FREQUENCY(100_000_000 * CLK_MULTIPLY_FACTOR / CLK_DIVISION_FACTOR)
    ) uart_inst_0 (
        .clk(clk),
        .rst(rst_held),
        .data_stream_in(data_stream_in),
        .data_stream_in_stb(data_stream_in_stb),
        .data_stream_in_ack(data_stream_in_ack),
        .data_stream_out(data_stream_out),
        .data_stream_out_stb(data_stream_out_stb),
        .tx(rx),
        .rx(tx)
    );
    
    // cache instance
    cache # (.WIDTH(WIDTH), .HEIGHT(HEIGHT)) cache_inst_0 (
        .clk(clk),
        .rst(rst_held),
        // interfacing with memory
        .mem_addr(mem_addra),
        .mem_do(mem_doa),
        .mem_di(mem_dia),
        .mem_en(mem_ena),
        .mem_we(mem_wea),
        // interfacing with acc
        .en(en),
        .we(we),
        .di(dataW),
        .doa(dataRa),
        .dob(dataRb),
        .doc(dataRc),
        .row_cached(row_cached),
        .finish(finish)
    );

    // Memory3 instance
    memory3 #(.ADDR_WIDTH(16)) memory3_inst_0 (
        .clk(clk),
        .rst(rst_held),
        // Port a (accelerator)
        .ena(mem_ena),
        .wea(mem_wea),
        .addra(mem_addra),
        .dia(mem_dia),
        .doa(mem_doa),
        // Port b (uart/controller)
        .enb(mem_enb),
        .web(mem_web),
        .addrb(mem_addrb),
        .dib(mem_dib),
        .dob(mem_dob)
    );



endmodule
