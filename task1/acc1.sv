// -----------------------------------------------------------------------------
//
//  Title      :  Edge-Detection design project - task 1.
//             :
//  Developers :  Roland Domján - s254360@student.dtu.dk
//             :  YOUR NAME HERE - s??????@student.dtu.dk
//             :
//  Purpose    :  This design contains an entity for the accelerator that must be build
//             :  in task one of the Edge Detection design project.
//             :
//  Revision   :  1.0   ??-??-??     Final version
//             :
//
// ----------------------------------------------------------------------------//

//------------------------------------------------------------------------------
// The module for task one. 
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

    typedef enum bit [3:0] {init, read0, read1, read, write, fin} state_t;

    state_t state, state_next;

    parameter MAX_ADDR = ((288 * 352) / 4) - 1;  
    logic [$clog2(MAX_ADDR)-1:0] addr_r_cnt, addr_r_next; // form 0 to 288*352/4-1
    logic [$clog2(MAX_ADDR*2)-1:0] addr_w_cnt, addr_w_next; // 288*352/4-1 to 2x  
    logic [7:0] px1, px2, px3, px4;
    logic [31:0] data_in_cache, data_in_cache_next, data_out_cache, data_out_cache_next;
    logic writing;

    assign dataW               = data_out_cache;
    assign data_out_cache_next = {px4, px3, px2, px1};
    assign we                  = writing;

    always_comb begin : addressSelector
        if (writing) begin 
            addr = addr_w_cnt;
        end else begin
            addr = addr_r_cnt; 
        end
    end

    always_comb begin : FSM
        en          = 1'b0;
        writing     = 1'b0;
        finish      = 1'b0;
        state_next  = init;
        addr_r_next = addr_r_cnt;
        addr_w_next = addr_w_cnt;

        data_in_cache_next = data_in_cache;

        px1 = 8'd255 - data_in_cache[7:0];
        px2 = 8'd255 - data_in_cache[15:8];
        px3 = 8'd255 - data_in_cache[23:16];
        px4 = 8'd255 - data_in_cache[31:24];

        case (state) 
            init: begin
                addr_r_next        = 'h0;
                addr_w_next        = MAX_ADDR;
                data_in_cache_next = 32'b0;

                if (start) begin
                    state_next = read0;
                end else begin
                    state_next = init;
               end
            end
            read0: begin
                en          = 1'b1;
                addr_r_next = addr_r_cnt + 1'b1;
                state_next  = read1;
            end
            read1: begin
                en = 1'b1;
                state_next = write;
                data_in_cache_next = dataR;
            end
            read: begin
                if (addr_r_cnt >= MAX_ADDR + 1'b1) begin
                    addr_r_next = 'h0;
                    addr_w_next = MAX_ADDR;
                    state_next  = fin;
                end else begin
                    en          = 1'b1;
                    addr_r_next = addr_r_cnt + 1'b1;
                    state_next  = write;
                end
            end
            write: begin
                en                 = 1'b1;
                writing            = 1'b1;
                addr_w_next        = addr_w_cnt + 1'b1;
                data_in_cache_next = dataR;
                state_next         = read;
            end
            fin: begin
                finish = 1'b1;

                if (start) state_next = fin;
                else       state_next = init;
                
            end
            default: begin
                state_next = init;
            end
        endcase
    end

    always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
        state    <= init;
        addr_r_cnt <= 'h0;
        addr_w_cnt <= MAX_ADDR;
        data_in_cache <= 32'b0;
        data_out_cache <= 32'b0;
      end else begin
        state    <= state_next;
        addr_r_cnt <= addr_r_next;
        addr_w_cnt <= addr_w_next;
        data_in_cache <= data_in_cache_next;
        data_out_cache <= data_out_cache_next;
      end
    end
endmodule
