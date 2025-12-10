module ula (
    input signed [15:0] A, B,
    input [2:0] param,
    output reg [16:0] S
);


    always @(*) begin
        case (param)
            //Soma
            3'b001: S = A + B; //ADD   
            3'b010: S = A + B; //ADDI

            //Subtração
            3'b011: S = A - B; //SUB
            3'b100: S = A - B; //SUBI

            //Multiplicação
            3'b101: S = A * B; //MUL

            default: S = 16'b0;
        endcase
    end
    
endmodule


