module binarioParaBCD (
    input [15:0] binario,
    output reg [3:0] dezenaDeMilhar, milhar, centena, dezena, unidade
);
    //double dabble 
    integer i;
    reg [19:0] bcd; 

    always @(binario) begin
        bcd = 20'b0;
        for (i = 15; i >= 0; i = i - 1) begin
            //adiciona 3 se o dígito for maior ou igual a 5
            if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;
            if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;
            if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
            if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
            if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;

            //shift left
            bcd = bcd << 1;
            bcd[0] = binario[i];
        end

        unidade = bcd[3:0];
        dezena = bcd[7:4];
        centena = bcd[11:8];
        milhar = bcd[15:12];
        dezenaDeMilhar = bcd[19:16];
    end

endmodule