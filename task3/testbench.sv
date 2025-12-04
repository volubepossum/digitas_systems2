// -----------------------------------------------------------------------------
// SystemVerilog Testbench for task 2 of the Edge-Detection design project
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module testbench;
    // Clock and rst signals
    logic clk;
    logic rst;
    logic StopSimulation = 0;
    localparam string load_file_name = "/home/roland/Documents/vivado/02203_A2_SystemVerilog/other_images/kaleidoscope.pgm"; // Path to the input PGM file
    localparam int WIDTH  = 352;
    localparam int HEIGHT = 288;
    // Accelerator and memory signals
    logic [31:0] dataRa, dataRb, dataRc;
    logic [31:0] dataW;
    logic en;
    logic we;
    logic start;
    logic finish;
    logic mem_ena, mem_wea;
    logic [15:0] mem_addra;
    logic [31:0] mem_doa, mem_dia;

    logic row_cached;

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

    // Instantiate clock generator
    clock #(.PERIOD(80)) SysClk (
        .clk(clk),
        .stop(StopSimulation)
    );

    // Instantiate accelerator
    acc # (.WIDTH(WIDTH), .HEIGHT(HEIGHT)) Accelerator (
        .clk(clk),
        .rst(rst_held),
        .dataRa(dataRa),
        .dataRb(dataRb),
        .dataRc(dataRc),
        .dataW(dataW),
        .row_cached(row_cached),
        .en(en),
        .we(we),
        .start(start),
        .finish(finish)
    );

    // Instantiate memory
    memory1 #(.load_file_name(load_file_name)) Memory (
        .clk(clk),
        .en(mem_ena),
        .we(mem_wea),
        .addr(mem_addra),
        .dataW(mem_dia),
        .dataR(mem_doa),
        .dump_image(finish)
    );

    // cache instance
    cache # (.WIDTH(WIDTH), .HEIGHT(HEIGHT)) Cache (
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
        .row_cached(row_cached),
        .di(dataW),
        .doa(dataRa),
        .dob(dataRb),
        .doc(dataRc),
        .finish(finish)
    );

    // Reset and start logic
    initial begin
        rst = 1;
        start = 0;
        #180 rst = 0;

        // Wait for rst deassertion and clock edge
        wait(~rst_held);

        // wait a few extra clocks
        repeat (2) @(posedge clk);

        start = 1;

        // Wait for accelerator to finish
        wait (finish);
        start = 0;

        @(posedge clk);
        $display("Test finished successfully! Simulation Stopped!");
        StopSimulation = 1;
        $finish;
    end
endmodule
