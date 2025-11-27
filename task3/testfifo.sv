`timescale 1ns / 1ps

module testfifo;

    // DUT signals
    logic        clk;
    logic        rst;
    logic [31:0] di;
    logic        wen;
    logic [31:0] dout;
    logic        ren;



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

    // Instantiate DUT
    fifo dut (
        .clk(clk),
        .rst(rst_held),
        .di(di),
        .wen(wen),
        .dout(dout),
        .ren(ren)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100 MHz
    end

    // Test sequence
    initial begin
        integer i;
        logic [31:0] expected;
        
        // Initial values
        rst = 1;
        wen = 0;
        ren = 0;
        di  = 0;

        $display("\n--- Starting FIFO Test ---");

        #180 rst = 0;
        wait(~rst_held);
        repeat (2) @(posedge clk);
        $display("Reset complete.");

        // ----------------------------------------------------------
        // WRITE PHASE
        // ----------------------------------------------------------
        $display("\nWriting 5 values into FIFO...");
        for (i = 0; i < 5; i++) begin
            @(posedge clk);
            di  = 32'hA000_0000 + i;
            wen = 1;
        end
        @(posedge clk);
        wen = 0;
        $display("Write phase complete.");

        // ----------------------------------------------------------
        // READ PHASE
        // ----------------------------------------------------------
        $display("\nReading back values...");
        for (i = 0; i < 5; i++) begin
            @(posedge clk);
            expected = 32'hA000_0000 + i;
            ren = 1;
            @(posedge clk);  // wait one cycle for output register
            ren = 0;


            if (dout !== expected)
                $display("FAIL: Expected %h but got %h at index %0d", expected, dout, i);
            else
                $display("PASS: Read correct value %h", dout);
            @(posedge clk);  // wait another cycle for output register
            @(posedge clk);  // wait another cycle for output register
        end

        $display("\n--- FIFO Test Complete ---\n");
        $finish;
    end

endmodule
