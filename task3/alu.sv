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
    logic [9:0] o_next;
    logic [8:0] ac, ac_next;

    always_comb begin : COMP
        // ac_next = a + c;
        ac      = a + c;
        o_next  = {b, 1'b0} + ac;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o <= 10'b0;
            // ac <= 9'b0;
        end else begin
            o <= o_next;
            // ac <= ac_next;
        end
    end
endmodule

