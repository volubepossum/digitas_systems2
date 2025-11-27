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
    output logic [31:0] doc  // memory read, current output
);

    localparam MAX_ADDR  = ((WIDTH * HEIGHT) / 4) - 1; // number of registers for 1 frame
    localparam ROW_WIDTH = WIDTH / 4;                  // number of registers for 1 row

    logic [31:0] mem_do_reorder;
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
    assign doc = mem_do_reorder;
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

    always_ff @(posedge clk or posedge rst) begin
      if (rst) begin
        addr_r_cnt <= '0;
        addr_w_cnt <= MAX_ADDR;
        fifo_cnt   <= '0;
        read_ready <= 2'b0;

        // reset pipelined outputs
        mem_addr <= '0;
        mem_di   <= '0;
        mem_en   <= 1'b0;
        mem_we   <= 1'b0;
      end else begin
        addr_r_cnt <= addr_r_next;
        addr_w_cnt <= addr_w_next;
        fifo_cnt   <= fifo_cnt_next;
        read_ready <= read_ready_next;

        // update pipelined mem outputs using non-blocking assignment shortcut
        mem_addr <= mem_addr_next;
        mem_di   <= mem_di_next;
        mem_en   <= mem_en_next;
        mem_we   <= mem_we_next;
      end
    end

    logic [31:0] fifo_transfer;
    assign dob = fifo_transfer; // use the middle value for the last row's output
    fifo # ()
    fifo_inst_a (
        .clk(clk),
        .rst(rst),
        .di(fifo_transfer),
        .ren(fifo_r_en),
        .dout(doa),               // use the a fifo for the previous row's output
        .wen(fifo_w_en)
    );
    fifo # ()
    fifo_inst_b (
        .clk(clk),
        .rst(rst),
        .di(mem_do_reorder),
        .ren(fifo_r_en),
        .dout(fifo_transfer),
        .wen(fifo_w_en)
    );
endmodule