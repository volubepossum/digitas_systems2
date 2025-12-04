// when enabled add the data in to cache. 



module cache #(
    parameter WIDTH  = 352, // width of frame
    parameter HEIGHT = 288 // height of frame
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

    localparam MAX_ADDR  = ((WIDTH * HEIGHT) / 4); // number of registers for 1 frame
    localparam ROW_WIDTH = WIDTH / 4;              // number of registers for 1 row

    logic [31:0] mem_do_reorder;
    logic [31:0] doc_buf;

    logic [15:0] addr_r_cnt, addr_r_next; // form 0 to 288*352/4-1
    logic [15:0] addr_w_cnt, addr_w_next; // 288*352/4 to 2x 
    logic [$clog2(ROW_WIDTH) - 1:0] fifo_cnt, fifo_cnt_next; 
    logic [ 1:0] read_ready, read_ready_next;
    logic fifo_r_en, fifo_w_en;

    logic [15:0] mem_addr_next;
    logic [31:0] mem_di_next;
    logic        mem_en_next;
    logic        mem_we_next;

    assign mem_do_reorder = {mem_do[7:0], mem_do[15:8], mem_do[23:16], mem_do[31:24]};
    assign doc            = doc_buf;
    assign row_cached = fifo_cnt >= ROW_WIDTH;

    assign read_ready_next[1] = read_ready[0];
    assign fifo_w_en          = read_ready[1];

    always_comb begin : addressManagement
        read_ready_next[0] = 1'b0;
        addr_r_next        = addr_r_cnt;
        addr_w_next        = addr_w_cnt;
        fifo_cnt_next      = fifo_cnt;
        fifo_r_en          = 1'b0;

        mem_addr_next = mem_addr;
        mem_di_next   = mem_di;
        mem_en_next   = 1'b0;
        mem_we_next   = 1'b0;

        if (en) begin
            mem_en_next = 1'b1;
            if (we) begin
                mem_we_next = 1'b1;
                mem_addr_next = addr_w_cnt;
                mem_di_next   = {di[7:0], di[15:8], di[23:16], di[31:24]};
                addr_w_next = addr_w_cnt + 1;
            end else begin // read
                mem_we_next = 1'b0;
                mem_addr_next = addr_r_cnt;
                addr_r_next = addr_r_cnt + 1;
                read_ready_next[0] = 1'b1;
                if (row_cached) begin
                    fifo_r_en = 1'b1;
                end else begin
                    fifo_cnt_next = fifo_cnt + 1;
                end
            end
        end
    end
    always_ff @( posedge clk ) begin // this mem block doesn't like being async reset for the address
        if (rst) begin
            mem_addr <= '0;
            mem_di   <= '0;
            mem_en   <= 1'b0;
            mem_we   <= 1'b0;
        end else begin
            mem_addr <= mem_addr_next;
            mem_di   <= mem_di_next;
            mem_en   <= mem_en_next;
            mem_we   <= mem_we_next;
        end
    end
    always_ff @(posedge clk or posedge rst) begin
        if (rst | finish) begin
            addr_r_cnt <= '0;
            addr_w_cnt <= MAX_ADDR;
            fifo_cnt   <= '0;
            read_ready <= 2'b0;
        end else begin
            addr_r_cnt <= addr_r_next;
            addr_w_cnt <= addr_w_next;
            fifo_cnt   <= fifo_cnt_next;
            read_ready <= read_ready_next;
        end
    end

    logic [31:0] fifo_transfer;
    assign dob = fifo_transfer; // use the middle value for the last row's output

    // 1-cycle pipeline on FIFO write side
    logic [31:0] fifo_a_di_buf, fifo_b_di_buf;
    logic        fifo_w_en_buf;

    always_ff @(posedge clk) begin
        if (rst) begin
            fifo_a_di_buf <= '0;
            fifo_b_di_buf <= '0;
            fifo_w_en_buf <= 1'b0;
            doc_buf       <= '0;
        end else begin
            fifo_w_en_buf <= fifo_w_en;  // delayed write enable
            if (read_ready[1]) begin
                doc_buf <= mem_do_reorder;
            end
            if (fifo_w_en) begin
                fifo_a_di_buf <= fifo_transfer;      // previous row
                fifo_b_di_buf <= mem_do_reorder;     // current row
            end
        end
    end

    fifo # ()
    fifo_inst_a (
        .clk (clk),
        .rst (rst),
        .wen (fifo_w_en_buf),
        .di  (fifo_a_di_buf),
        .ren (fifo_r_en),
        .dout(doa)               // use the a fifo for the previous row's output
    );
    
    fifo # ()
    fifo_inst_b (
        .clk (clk),
        .rst (rst),
        .wen (fifo_w_en_buf),
        .di  (fifo_b_di_buf),
        .ren (fifo_r_en),
        .dout(fifo_transfer)
    );
endmodule