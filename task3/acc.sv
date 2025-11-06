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


module acc (
    input  logic        clk,        // The clock.
    input  logic        reset,      // The reset signal. Active high.
    output logic [15:0] addr,       // Address bus for data (halfword_t).
    input  logic [31:0] dataR,      // The data bus (word_t).
    output logic [31:0] dataW,      // The data bus (word_t).
    output logic        en,         // Request signal for data.
    output logic        we,         // Read/Write signal for data.
    input  logic        start,
    output logic        finish
);

    typedef enum {INIT, READ0, READ1, READ, WRITE, FIN} state_t;

    state_t state, state_next;

    parameter MAX_ADDR = ((288 * 352) / 4) - 1;  
    logic [15:0] addr_r_cnt, addr_r_next; // form 0 to 288*352/4-1
    logic [15:0] addr_w_cnt, addr_w_next; // 288*352/4-1 to 2x  
    logic [15:0] addr_next;  
    logic [7:0] px1, px2, px3, px4;
    logic [31:0] data_r_buffer, data_r_buffer_next, data_w_buffer, data_w_buffer_next;
    logic en_next, we_next;

    assign dataW = data_w_buffer;
    assign data_r_buffer_next = dataR;

    always_comb begin : calc
        px1 = 8'd255 - data_r_buffer[7:0];
        px2 = 8'd255 - data_r_buffer[15:8];
        px3 = 8'd255 - data_r_buffer[23:16];
        px4 = 8'd255 - data_r_buffer[31:24];
        data_w_buffer_next = {px4, px3, px2, px1};
    end

    always_comb begin : FSM
        en_next     = 1'b0;
        we_next     = 1'b0;
        finish      = 1'b0;
        state_next  = INIT;
        addr_next   = '0;
        addr_r_next = addr_r_cnt;
        addr_w_next = addr_w_cnt;
       
        case (state) 
            INIT: begin
                addr_r_next        = '0;
                addr_w_next        = MAX_ADDR;

                if (start) begin
                    state_next  = READ0;
                    en_next     = 1'b1;
                    addr_next   = addr_r_cnt;
                    addr_r_next = addr_r_cnt + 1;
                end else begin
                    state_next = INIT;
               end
            end
            READ0: begin
                state_next  = READ1;
                en_next     = 1'b1;
                addr_next   = addr_r_cnt;
                addr_r_next = addr_r_cnt + 1'b1;
            end
            READ1: begin
                state_next  = WRITE;
                en_next     = 1'b1;
                we_next     = 1'b1;
                addr_next   = addr_w_cnt;
                addr_w_next = addr_w_cnt + 1;
            end
            READ: begin
                if (addr_r_cnt >= MAX_ADDR + 1'b1) begin
                    state_next  = FIN;
                    addr_r_next = '0;
                    addr_w_next = MAX_ADDR;
                end else begin
                    state_next  = WRITE;
                    en_next     = 1'b1;
                    we_next     = 1'b1;
                    addr_next   = addr_w_cnt;
                    addr_w_next = addr_w_cnt + 1'b1;
                end
            end
            WRITE: begin
                state_next  = READ;
                en_next     = 1'b1;
                addr_next   = addr_r_cnt;
                addr_r_next = addr_r_cnt + 1'b1;
            end
            FIN: begin
                finish = 1'b1;
                if (start) state_next = FIN;
                else       state_next = INIT;
            end
            default: begin
                state_next = INIT;
            end
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
        state         <= INIT;
        addr          <= '0;
        addr_r_cnt    <= '0;
        addr_w_cnt    <= MAX_ADDR;
        en            <= 1'b0;
        we            <= 1'b0;
        data_r_buffer <= 32'b0;
        data_w_buffer <= 32'b0;
      end else begin
        state         <= state_next;
        addr          <= addr_next;
        addr_r_cnt    <= addr_r_next;
        addr_w_cnt    <= addr_w_next;
        en            <= en_next;
        we            <= we_next;
        data_r_buffer <= data_r_buffer_next;
        data_w_buffer <= data_w_buffer_next;
      end
    end
endmodule
