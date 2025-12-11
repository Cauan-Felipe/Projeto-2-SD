module debounce_Botao(
    input clk, botaoAgora,
    output reg botaoPressionado
);

    //debounce de ~10ms
    reg [19:0] contador = 20'b0;
    reg botaoAnterior = 1'b0;
    reg botaoEstavel = 1'b0;

    always @(posedge clk) begin
        if (botaoAgora != botaoAnterior) begin
            if (contador < 20'd500_000) begin
                contador <= contador + 1;
            end else begin
                botaoEstavel <= botaoAgora;
                contador <= 20'b0;
            end
        end else begin
            contador <= 20'b0;
    end

    //detecta borda de subida
    botaoAnterior <= botaoEstavel;

    if (botaoEstavel && !botaoAnterior) begin
        botaoPressionado <= 1'b1;
    end else begin
        botaoPressionado <= 1'b0;
    end

    end

endmodule