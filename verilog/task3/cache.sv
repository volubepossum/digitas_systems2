// when enabled add the data in to cache. 



module cache #(
    parameter WIDTH  = 352, // width of frame
    parameter HEIGHT = 288, // height of frame
    parameter MEMORY_DELAY = 2  // pipeline stages for read_ready
    // parameter PX_REG = 4    // pixels per image
) (
    input  logic clk,
    input  logic rst,

    // signals for memory
    output logic [15:0] mem_addr,   // Address bus for data (halfword_t).
    input  logic [31:0] mem_do,     // The data bus (word_t). This is read from memory.
    output logic [31:0] mem_di,     // The data bus (word_t). Write this to memory.
    output logic        mem_en,     // Request signal for data.
    output logic        mem_we,     // Read/Write signal for data.

    // signals for accelerator
    input  logic        en,
    input  logic        we,
    input  logic [31:0] di,  // write this to memory
    output logic        row_cached, // if there is one row cached
    output logic [31:0] doa, // fifo a read, cached output
    output logic [31:0] dob, // fifo b read, cached output
    output logic [31:0] doc,  // memory read, current output

    input  logic        finish // finish signal. addresses are to be reset, new operation will make sure that everything else isn't corrupted
);

    genvar i;
    localparam MAX_ADDR  = ((WIDTH * HEIGHT) / 4); // number of registers for 1 frame
    localparam ROW_WIDTH = WIDTH / 4;              // number of registers for 1 row

    logic [31:0] mem_do_reorder;

    logic [15:0] addr_r_cnt, addr_r_next; // form 0 to 288*352/4-1
    logic [15:0] addr_w_cnt, addr_w_next; // 288*352/4 to 2x 
    
    logic read_ready, read_ready_next;
    logic [MEMORY_DELAY-1:0] read_ready_buf;

    logic two_row_cached;
    
    logic fifo_r_en_a, fifo_w_en_a;
    logic fifo_r_en_b, fifo_w_en_b;
    logic [1:0] fifo_b_read_delay;  // 2-cycle delay for FIFO B read output valid

    logic [15:0] mem_addr_next;
    logic [31:0] mem_di_next;
    logic        mem_en_next;
    logic        mem_we_next;

    logic fifo_w_en_b_delayed;  // Add delayed write enable
    logic [31:0] mem_do_reorder_buf;

    assign mem_do_reorder = {mem_do[7:0], mem_do[15:8], mem_do[23:16], mem_do[31:24]};
    assign mem_di_next    = {di[7:0], di[15:8], di[23:16], di[31:24]};
    assign doc            = mem_do_reorder;
    assign row_cached     = addr_r_cnt > ROW_WIDTH - 1;
    assign two_row_cached = addr_r_cnt > (2 * ROW_WIDTH) - 1;
    assign fifo_w_en_a    = fifo_b_read_delay[1];
    always_comb begin : addressManagement
        read_ready_next = 1'b0;
        addr_r_next     = addr_r_cnt;
        addr_w_next     = addr_w_cnt;
        mem_addr_next   = mem_addr;
        mem_en_next     = 1'b0;
        mem_we_next     = 1'b0;
        fifo_r_en_a     = 1'b0;
        fifo_r_en_b     = 1'b0;


        if (en) begin
            mem_en_next = 1'b1;
            if (we) begin
                mem_we_next   = 1'b1;
                mem_addr_next = addr_w_cnt;
                addr_w_next   = addr_w_cnt + 1;
            end else begin // read
                mem_we_next     = 1'b0;
                mem_addr_next   = addr_r_cnt;
                addr_r_next     = addr_r_cnt + 1;
                read_ready_next = 1'b1;
                if (row_cached)     fifo_r_en_b = 1'b1;
                if (two_row_cached) fifo_r_en_a = 1'b1;
            end
        end
    end

    // Synchronous shift register for read_ready delay
    generate   
        for (i = 0; i < MEMORY_DELAY-1; i = i + 1) begin
            always_ff @(posedge clk or posedge rst) begin
                if (rst) begin
                    read_ready_buf[i] <= '0;
                end else begin
                    read_ready_buf[i] <= read_ready_buf[i+1];
                end
            end
        end
        always_ff @(posedge clk or posedge rst) begin
            if (rst) read_ready_buf[MEMORY_DELAY-1] <= '0;
            else     read_ready_buf[MEMORY_DELAY-1] <= read_ready_next;
        end
    endgenerate

    assign read_ready  = read_ready_buf[0];

    // Add extra flip-flop for FIFO B write enable
    always_ff @(posedge clk) begin
        if (rst) begin
            fifo_w_en_b_delayed <= '0;
            mem_do_reorder_buf  <= '0;
        end else begin
            fifo_w_en_b_delayed <= read_ready;
            mem_do_reorder_buf  <= mem_do_reorder;
        end
    end

    assign fifo_w_en_b = fifo_w_en_b_delayed;  // Use delayed version

    always_ff @( posedge clk ) begin // this mem block doesn't like being async reset for the address
        if (rst) begin
            mem_addr          <= '0;
            mem_di            <= '0;
            mem_en            <= 1'b0;
            mem_we            <= 1'b0;
            fifo_b_read_delay <= 2'b0;

        end else begin
            mem_addr <= mem_addr_next;
            mem_di   <= mem_di_next;
            mem_en   <= mem_en_next;
            mem_we   <= mem_we_next;
            // Shift register to track when FIFO B output is valid (2 clocks after read enable)
            fifo_b_read_delay <= {fifo_b_read_delay[0], fifo_r_en_b};
        end
    end
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst | finish) begin
            addr_r_cnt <= '0;
            addr_w_cnt <= MAX_ADDR;
        end else begin
            addr_r_cnt <= addr_r_next;
            addr_w_cnt <= addr_w_next;
        end
    end

    logic [31:0] fifo_b_out;
    assign dob = fifo_b_out; // use the middle value for the last row's output

    fifo # ()
    fifo_inst_a (
        .clk (clk),
        .rst (rst || (addr_r_cnt > ( MAX_ADDR + ROW_WIDTH ))),
        .wen (fifo_w_en_a),
        .di  (fifo_b_out),      
        .ren (fifo_r_en_a),
        .dout(doa)
    );
    
    fifo # ()
    fifo_inst_b (
        .clk (clk),
        .rst (rst || (addr_r_cnt > ( MAX_ADDR + ROW_WIDTH ))),
        .wen (fifo_w_en_b),
        .di  (mem_do_reorder_buf),
        .ren (fifo_r_en_b),
        .dout(fifo_b_out)
    );
endmodule