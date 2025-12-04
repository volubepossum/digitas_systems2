// ---------------------------------------------------------------------------//
//
//  Title      :  Edge-Detection design project - task 3.
//             :
//  Developers :  Roland Domján - s254360@student.dtu.dk
//             :
//  Purpose    :  This design contains an entity for computing the basic computation
//             :  in the edge detection: a + 2b + c
//             :
//  Revision   :  1.0   ??-??-??     Final version
//             :
//
// ----------------------------------------------------------------------------//

module alu (
    input  logic       clk,
    input  logic       rst,

    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic [7:0] c,
    output logic [9:0] o
);
    logic [9:0] o_next, b_buf, b_next;
    logic [8:0] ac, ac_next;

    always_comb begin : COMP
        ac_next = a + c;
        b_next  = b;
        // ac      = a + c;
        o_next  = {b_buf, 1'b0} + ac;
        // o_next  = {b, 1'b0} + ac;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o <= 10'b0;
            ac <= 9'b0;
            b_buf <= 8'b0;
        end else begin
            o <= o_next;
            ac <= ac_next;
            b_buf <= b_next;
        end
    end
endmodule

