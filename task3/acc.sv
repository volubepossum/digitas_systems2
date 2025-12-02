// -----------------------------------------------------------------------------
//
//  Title      :  Edge-Detection design project - task 3.
//             :
//  Developers :  Roland Domján - s254360@student.dtu.dk
//             :  YOUR NAME HERE - s??????@student.dtu.dk
//             :
//  Purpose    :  This design contains an entity for the accelerator that must be build
//             :  in task three of the Edge Detection design project.
//             :
//  Revision   :  1.0   ??-??-??     Final version
//             :
//
// ----------------------------------------------------------------------------//

//------------------------------------------------------------------------------
// The module for task three. 
//------------------------------------------------------------------------------


module acc #(
    parameter WIDTH  = 352, // width of frame
    parameter HEIGHT = 288 // height of frame
    // parameter PX_REG = 4    // pixels per image
) (
    input  logic        clk,        // The clock.
    input  logic        rst,      // The rst signal. Active high.
    input  logic [31:0] dataRa,     // The data bus (word_t).
    input  logic [31:0] dataRb,     // The data bus (word_t).
    input  logic [31:0] dataRc,     // The data bus (word_t).
    output logic [31:0] dataW,      // The data bus (word_t).
    output logic        en,         // Request signal for data.
    output logic        we,         // Read/Write signal for data.
    input  logic        row_cached,
    input  logic        start,
    output logic        finish
);

    genvar i;
    localparam WAIT_LENGTH = 5;                          // should be at least 2, and odd
    localparam MAX_ADDR    = ((WIDTH * HEIGHT) / 4) - 1; // number of registers for 1 frame
    localparam ROW_WIDTH   = WIDTH / 4;                  // number of registers for 1 row


    /////////
    // FSM //
    /////////
    typedef enum {
        INIT, 
        FILL_FIFOS, 
        WAIT,
        READ, 
        WRITE,
        FIN
    } state_t;

    state_t state, state_next;

    logic read_ready, read_ready_next;  // signals are ready to be inputted to alu - dataR(abc)
    logic [2:0] read_ready_buf;         // 2-stage buffer: read_ready_next -> buf[0] -> buf[1] (read_ready)
    logic [$clog2(WAIT_LENGTH)-1: 0] wait_cnt, wait_next;                  
    logic [$clog2(HEIGHT)   -1:0] row_cnt, row_next;
    logic [$clog2(ROW_WIDTH)-1:0] col_cnt, col_next;

    always_comb begin : FSM
        state_next = INIT;
        wait_next  = '0;
        read_ready_next     = 1'b0;
        en         = 1'b0;
        we         = 1'b0;
        finish     = 1'b0;
        case (state)
            INIT: begin
                if (start) begin
                    state_next = FILL_FIFOS;
                end else begin
                    state_next = INIT;
                end
            end 
            FILL_FIFOS: begin
                en = 1;
                if (row_cached) begin
                    state_next = WAIT;
                    read_ready_next = 1;
                end else begin
                    state_next = FILL_FIFOS;
                end
            end
            WAIT: begin
                read_ready_next = 1;
                en     = 1;
                if (wait_cnt == WAIT_LENGTH - 1) begin
                    state_next = WRITE;
                end else begin
                    state_next = WAIT;
                    wait_next  = wait_cnt + 1;
                end
            end
            READ: begin
                en = 1;
                state_next = WRITE;
                read_ready_next = 1;
            end
            WRITE: begin
                en = 1;
                we = 1;
                if (row_cnt == HEIGHT && col_cnt == ROW_WIDTH -1) state_next = FIN;
                else                                              state_next = READ;
            end
            FIN: begin
                finish = 1'b1;
                if (start) state_next = FIN;
                else       state_next = INIT;
            end            
            default: state_next = INIT;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
      if (rst) begin
        state          <= INIT;
        wait_cnt       <= '0;
        read_ready_buf <= 2'b0;
      end else begin
        state          <= state_next;
        wait_cnt       <= wait_next;
        read_ready_buf <= {read_ready_buf[1], read_ready_buf[0], read_ready_next };
      end
    end
    assign read_ready = read_ready_buf[2];


    // input numbers to the alu
    logic [31:0] alu_in_a, alu_in_b, alu_in_c;
    logic [31:0] alu_in_a_next, alu_in_b_next, alu_in_c_next;

    always_comb begin : ASSIGN_ALU
        alu_in_a_next = alu_in_a;
        alu_in_b_next = alu_in_b;
        alu_in_c_next = alu_in_c;

        case ({row_cnt == 0, row_cnt == HEIGHT-1})
            2'b10: begin // top row 
                alu_in_a_next = dataRb;
                alu_in_b_next = dataRb;
                alu_in_c_next = dataRc;
            end
            2'b00: begin // middle rows 
                alu_in_a_next = dataRa;
                alu_in_b_next = dataRb;
                alu_in_c_next = dataRc;    
            end
            2'b01: begin // bottom row 
                alu_in_a_next = dataRa;
                alu_in_b_next = dataRb;
                alu_in_c_next = dataRb;
            end
            default: begin
                alu_in_a_next = dataRa;
                alu_in_b_next = dataRb;
                alu_in_c_next = dataRc; 
            end
        endcase
    end

    always_ff @( posedge clk or posedge rst ) begin 
        if (rst) begin
            alu_in_a <= '0;
            alu_in_b <= '0;
            alu_in_c <= '0;
        end else if (read_ready) begin
            alu_in_a <= alu_in_a_next;
            alu_in_b <= alu_in_b_next;
            alu_in_c <= alu_in_c_next;
        end
    end


    /////////
    // ALU //
    /////////


    function automatic logic [9:0] abs_sub
    (
        input logic [9:0] a,
        input logic [9:0] b
    );
        logic signed [10:0] diff;
        diff = {1'b0, a} - {1'b0, b};      // allow signed range
        abs_sub = diff[10] ? (~diff + 1) : diff;   // two’s complement abs
    endfunction
  
    // x derivative
    logic [39:0] x_der, x_der_next;
    logic [49:0] x_der_pre_buff, x_der_pre_next;

    assign x_der_pre_next[49:40] = x_der_pre_buff[9:0];

    logic x_alus_ready, x_alus_ready_buf;

    generate
    	for (i = 0; i < 4; i = i + 1) begin
            alu # () alu_inst_x (
                .clk(clk),
                .rst(rst),
                .a(alu_in_a[8*(i+1)-1:8*i]),
                .b(alu_in_b[8*(i+1)-1:8*i]),
                .c(alu_in_c[8*(i+1)-1:8*i]),
                .o(x_der_pre_next[10*(i+1)-1:10*i])
          );
		end
    endgenerate

   always_comb begin
        unique case ({col_cnt == 2, col_cnt == 1})
            2'b10: begin // left column
                x_der_next[39:30] = abs_sub(x_der_pre_buff[29:20], x_der_pre_buff[39:30]);
                x_der_next[29:20] = abs_sub(x_der_pre_buff[19:10], x_der_pre_buff[39:30]);
                x_der_next[19:10] = abs_sub(x_der_pre_buff[ 9: 0], x_der_pre_buff[29:20]);
                x_der_next[ 9: 0] = abs_sub(x_der_pre_next[39:30], x_der_pre_buff[19:10]);
            end

            2'b00: begin // middle
                x_der_next[39:30] = abs_sub(x_der_pre_buff[29:20], x_der_pre_buff[49:40]);
                x_der_next[29:20] = abs_sub(x_der_pre_buff[19:10], x_der_pre_buff[39:30]);
                x_der_next[19:10] = abs_sub(x_der_pre_buff[ 9: 0], x_der_pre_buff[29:20]);
                x_der_next[ 9: 0] = abs_sub(x_der_pre_next[39:30], x_der_pre_buff[19:10]);
            end

            2'b01: begin // right
                x_der_next[39:30] = abs_sub(x_der_pre_buff[29:20], x_der_pre_buff[49:40]);
                x_der_next[29:20] = abs_sub(x_der_pre_buff[19:10], x_der_pre_buff[39:30]);
                x_der_next[19:10] = abs_sub(x_der_pre_buff[ 9: 0], x_der_pre_buff[29:20]);
                x_der_next[ 9: 0] = abs_sub(x_der_pre_buff[ 9: 0], x_der_pre_buff[19:10]);
            end

            default: begin
                x_der_next[39:30] = abs_sub(x_der_pre_buff[29:20], x_der_pre_buff[49:40]);
                x_der_next[29:20] = abs_sub(x_der_pre_buff[19:10], x_der_pre_buff[39:30]);
                x_der_next[19:10] = abs_sub(x_der_pre_buff[ 9: 0], x_der_pre_buff[29:20]);
                x_der_next[ 9: 0] = abs_sub(x_der_pre_next[39:30], x_der_pre_buff[19:10]);
            end
        endcase
    end
    
    always_ff @( posedge clk or posedge rst ) begin 
        if (rst) begin
            x_der            <= '0;
            x_der_pre_buff   <= '0;
            x_alus_ready     <= '0;
        end else begin    
            if (x_alus_ready) begin
                x_der          <= x_der_next;
                x_der_pre_buff <= x_der_pre_next;
            end
            x_alus_ready <= read_ready;
        end
    end

    // y derivative
    logic [39:0] y_der, y_der_next;
    // top (from in a) / bot (from in c) merged into one block to avoid duplication
    logic [39:0] y_alu_in_top_buff, y_alu_in_top_next;
    logic [47:0] y_alu_in_top;
    logic [39:0] y_der_pre_top;

    logic [39:0] y_alu_in_bot_buff, y_alu_in_bot_next;
    logic [47:0] y_alu_in_bot;
    logic [39:0] y_der_pre_bot;
    always_comb begin
        // prepare next words

        y_alu_in_top_next[39:32] = y_alu_in_top_buff[7:0];
        y_alu_in_top_next[31: 0] = alu_in_a;
        y_alu_in_bot_next[39:32] = y_alu_in_bot_buff[7:0];
        y_alu_in_bot_next[31: 0] = alu_in_c;

        unique case ({col_cnt == 1, col_cnt == 0})
            2'b10: begin // left column: replicate leftmost byte
                y_alu_in_top = {
                    y_alu_in_top_buff[31:24],
                    y_alu_in_top_buff[31: 0],
                    y_alu_in_top_next[31:24]
                };
                y_alu_in_bot = {
                    y_alu_in_bot_buff[31:24],
                    y_alu_in_bot_buff[31: 0],
                    y_alu_in_bot_next[31:24]
                };
            end
            2'b00: begin // middle
                y_alu_in_top = { y_alu_in_top_buff, y_alu_in_top_next[31:24] };
                y_alu_in_bot = { y_alu_in_bot_buff, y_alu_in_bot_next[31:24] };
            end
            2'b01: begin // right column: replicate rightmost byte
                y_alu_in_top = {
                    y_alu_in_top_buff,
                    y_alu_in_top_buff[ 7: 0]
                };
                y_alu_in_bot = {
                    y_alu_in_bot_buff,
                    y_alu_in_bot_buff[ 7: 0]
                };
            end
            default: begin
                y_alu_in_top = { y_alu_in_top_buff, y_alu_in_top_next[31:24] };
                y_alu_in_bot = { y_alu_in_bot_buff, y_alu_in_bot_next[31:24] };
            end
        endcase
    end
    
    generate
    	for (i = 0; i < 4; i = i + 1) begin
            alu # () alu_inst_y_top (
                .clk(clk),
                .rst(rst),
                .a(y_alu_in_top[8*(i+1)-1:8*(i+0)]),
                .b(y_alu_in_top[8*(i+2)-1:8*(i+1)]),
                .c(y_alu_in_top[8*(i+3)-1:8*(i+2)]),
                .o(y_der_pre_top[10*(i+1)-1:10*i])
          );
		end
    endgenerate

    generate
    	for (i = 0; i < 4; i = i + 1) begin
            alu # () alu_inst_y_bot (
                .clk(clk),
                .rst(rst),
                .a(y_alu_in_bot[8*(i+1)-1:8*(i+0)]),
                .b(y_alu_in_bot[8*(i+2)-1:8*(i+1)]),
                .c(y_alu_in_bot[8*(i+3)-1:8*(i+2)]),
                .o(y_der_pre_bot[10*(i+1)-1:10*i])
          );
		end
    endgenerate

    
    generate
    	for (i = 0; i < 4; i = i + 1) begin
            assign y_der_next [10*(i+1)-1:10*(i+0)] = abs_sub(y_der_pre_top[10*i+9:10*i], y_der_pre_bot[10*i+9:10*i]);
        end
    endgenerate

    always_ff @( posedge clk or posedge rst ) begin 
        if (rst) begin
            y_der             <= 32'b0;
            y_alu_in_top_buff <= 40'b0;
            y_alu_in_bot_buff <= 40'b0;
        end else begin
            if (read_ready) begin
                y_der             <= y_der_next;
                y_alu_in_top_buff <= y_alu_in_top_next;
                y_alu_in_bot_buff <= y_alu_in_bot_next;
            end 
        end
        
    end

    // output the alu results

    logic [31:0] alu_out, alu_out_next;
    logic [43:0] sum, sum_next;

    generate
    	for (i = 0; i < 4; i = i + 1) begin
            // sum of the corresponding 10-bit x and y derivatives -> 11 bits
            assign sum_next[11*(i+1)-1:11*i] = x_der[10*(i+1)-1:10*i] + y_der[10*(i+1)-1:10*i];

            // saturate to 8 bits: if top 3 bits of the 11-bit sum are non-zero -> 255
            assign alu_out_next[8*(i+1)-1:8*i] =
                (sum[11*i+10 : 11*i+8] == 3'b0) ? sum[11*i+7 : 11*i+0] : 8'd255;
        end
    endgenerate

    assign dataW = alu_out;

    always_ff @( posedge clk or posedge rst ) begin 
        if (rst) begin
            alu_out <= '0;
            sum     <= '0;
        end else if (read_ready) begin
            alu_out <= alu_out_next;
            sum     <= sum_next;
        end
    end


    //////////////////////////
    // row and col counters //
    //////////////////////////
    
    always_comb begin : ROW_COL_COUNTER
        row_next = row_cnt;
        col_next = col_cnt;
        if (read_ready) begin
            if (col_cnt == ROW_WIDTH - 1) begin
                col_next = 7'b0;
                row_next = row_cnt + 1'b1;
            end else col_next = col_cnt + 1'b1;
        end else if (state == INIT) begin
            row_next = 9'b0;
            col_next = 7'b0;
        end
    end

    always_ff @( posedge clk or posedge rst ) begin
        if (rst) begin
            row_cnt   <= 9'b0;
            col_cnt   <= 7'b0;
        end else begin
            row_cnt   <= row_next;
            col_cnt   <= col_next;
        end
    end
endmodule
