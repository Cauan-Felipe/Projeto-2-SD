module memoria(input clk, input enable, input ativar_clear,
	input [3:0] endereco_reg1, input [3:0] endereco_reg2, 
	input [3:0] endereco_escrita, input [15:0] conteudo_escrita, 
	output [15:0] conteudo_reg1, output [15:0] conteudo_reg2);

	// criando o banco de memória 16X16 
	reg [15:0] banco_mem [15:0];

	integer i; // para facilitar o clear

	// atualizando os endereços lidos assincronamente
	assign conteudo_reg1 = banco_mem[endereco_reg1];
	assign conteudo_reg2 = banco_mem[endereco_reg2];

	// escrita síncrona (sujeita ao clock e ao enable estar ativo)
	always@(posedge clk or posedge ativar_clear) begin 

		 if(ativar_clear) begin // processo de limpeza da memória

			 for (i = 0; i < 16; i = i + 1) begin
					banco_mem[i] <= 16'd0;
			 end
		 end

		 else if (enable) begin
			 banco_mem[endereco_escrita] <= conteudo_escrita; 
		 end
	end

endmodule