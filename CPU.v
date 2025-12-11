module CPU (
    input clk,
    input botao_ligar_agora,
    input botao_enviar_agora,
    input [17:0] instrucao_completa,

    output reg flag_clear_memoria, // Reset APENAS da memória
    output reg flag_escrever, // Saída para o banco de registradores

    // Saídas para o LCD
    output [7:0] lcd_data,
    output lcd_rs,
    output lcd_rw,
    output lcd_e,
    output lcd_on,
    output lcd_blon
);

    // --- Hardware DE2-115 ---
    assign lcd_on = 1'b1;
    assign lcd_blon = 1'b1;

    // Opcodes
    localparam OP_LOAD = 3'b000;
    localparam OP_ADD = 3'b001;
    localparam OP_ADDI = 3'b010;
    localparam OP_SUB = 3'b011;
    localparam OP_SUBI = 3'b100;
    localparam OP_MUL = 3'b101;
    localparam OP_CLEAR = 3'b110;
    localparam OP_DISPLAY = 3'b111;

    // Estados da FSM
    localparam S_DESLIGADO = 2'd0,
               S_AGUARDANDO = 2'd1,
               S_EXECUTANDO = 2'd2;

    reg [1:0] estado;
    reg sistema_ligado = 0;

    wire flag_ligar, flag_enviar;

    // Registradores LATCH (Seguram o valor p/ LCD não piscar)
    reg [2:0] lcd_opcode_latched;
    reg [3:0] lcd_logger_latched;
    reg [15:0] lcd_result_latched;

    // Dados Internos
    reg [3:0] reg_1_endereco, reg_2_endereco, escrita_endereco;
    wire [15:0] reg_1_conteudo, reg_2_conteudo;
    reg [15:0] operador_1, operador_2;
    wire [15:0] conteudo_resultado;

    // Decodificação direta das chaves
    wire [2:0] opcode_chaves = instrucao_completa[17:15];

    // Tratamento do Imediato
    wire sinal = instrucao_completa[6];
    wire [5:0] modulo_imediato_curto = instrucao_completa[5:0];
    wire [15:0] imediato_estendido;

    assign imediato_estendido =
        (sinal) ? -{10'd0, modulo_imediato_curto} :
                  {10'd0, modulo_imediato_curto};

    // --- INSTÂNCIAS ---

		 memoria banco_memoria (
		 .clk(clk),
		 .enable(flag_escrever),
		 .ativar_clear(flag_clear_memoria || ~sistema_ligado), // Se `flag_clear_memoria` for 1 OU se `sistema_ligado` for 0.
		 .endereco_reg1(reg_1_endereco),
		 .endereco_reg2(reg_2_endereco),
		 .endereco_escrita(escrita_endereco),
		 .conteudo_escrita(conteudo_resultado),
		 
		 // Portas de Saída (Outputs)
		 .conteudo_reg1   (reg_1_conteudo),
		 .conteudo_reg2   (reg_2_conteudo)
	);

    ula ula(
        .A(operador_1),
        .B(operador_2),
        .param(opcode_chaves),
        .S(conteudo_resultado)
    );

    lcd displayLCD(
			 // Módulo (lcd) Porta <- Sinal do Sistema (Instância)

			 // Entradas
			 .clk(clk),
			 .reset(~sistema_ligado),           // 'reset' do módulo lcd <- '~sistema_ligado'
			 .sinal_start(flag_enviar),               // 'sinal_start' do módulo lcd <- 'flag_enviar'
			 .entrada_op(lcd_opcode_latched),        // 'entrada_op' do módulo lcd <- 'lcd_opcode_latched'
			 .entrada_end(lcd_logger_latched),        // 'entrada_end' do módulo lcd <- 'lcd_logger_latched'
			 .entrada_valor(lcd_result_latched),        // 'entrada_valor' do módulo lcd <- 'lcd_result_latched'
			 
			 // Saídas
			 .saida_dados(lcd_data),                  // 'saida_dados' do módulo lcd <- 'lcd_data'
			 .lcd_rs(lcd_rs),
			 .lcd_rw(lcd_rw),
			 .lcd_e(lcd_e)
		);

    debounce_Botao detector_ligar (
        .clk(clk),
        .botaoAgora(botao_ligar_agora),
        .botaoPressionado(flag_ligar)
    );

    // Usamos um detector para o Enviar para garantir pulso único na lógica da CPU
    debounce_Botao detector_enviar(
        .clk(clk),
        .botaoAgora(botao_enviar_agora),
        .botaoPressionado(flag_enviar)
    );

    // --- LÓGICA DO SISTEMA (LIGAR/DESLIGAR) ---
    always@(posedge clk) begin
        if(flag_ligar)
            sistema_ligado <= ~sistema_ligado;
    end

    // --- FSM PRINCIPAL ---
    always@(posedge clk) begin
        if(~sistema_ligado) begin
            estado <= S_DESLIGADO;

            // Zera registradores visuais ao desligar
            lcd_opcode_latched <= 0;
            lcd_logger_latched <= 0;
            lcd_result_latched <= 0;
        end
        else begin
            case(estado)
                S_DESLIGADO: begin
                    estado <= S_AGUARDANDO;
                end

                S_AGUARDANDO: begin
                    // Se apertou enviar, executa e trava os dados
                    if (flag_enviar) begin
                        // 1. LATCH: Salva o estado atual das chaves para o LCD
                        lcd_opcode_latched <= opcode_chaves;
                        lcd_logger_latched <= escrita_endereco; // Definido na lógica combinacional abaixo

                        // 2. Define o resultado visual
                        if (opcode_chaves == OP_DISPLAY)
                            lcd_result_latched <= operador_1; // Valor lido
                        else
                            lcd_result_latched <= conteudo_resultado; // Resultado ULA

                        estado <= S_EXECUTANDO;
                    end
                end

                S_EXECUTANDO: begin
                    // Um ciclo para garantir escrita na memória, depois volta
                    estado <= S_AGUARDANDO;
                end
            endcase
        end
    end

    // --- LÓGICA COMBINACIONAL (PREPARAÇÃO DE DADOS) ---
    // Isso define o que entra na ULA e Memória antes mesmo do clock bater
    always@(*) begin
        // Defaults
        flag_escrever = 0;
        flag_clear_memoria = 0;
        reg_1_endereco = 0;
        reg_2_endereco = 0;
        escrita_endereco = 0;
        operador_1 = 0;
        operador_2 = 0;

        // Só processa se estiver ligado e nos estados principais
        if (estado == S_AGUARDANDO || estado == S_EXECUTANDO) begin

            // Ativa escrita/clear apenas no ciclo exato de execução
            if (estado == S_EXECUTANDO) begin
                if (opcode_chaves == OP_CLEAR)
                    flag_clear_memoria = 1;
                else if (opcode_chaves != OP_DISPLAY)
                    flag_escrever = 1;
            end

            // Configuração dos caminhos de dados baseada nas chaves
            case (opcode_chaves)
                OP_LOAD: begin
                    // Load Imediato
                    escrita_endereco = instrucao_completa[14:11];
                    operador_1 = 16'd0;
                    operador_2 = imediato_estendido;
                end

                OP_ADD,
                OP_SUB: begin
                    // Reg x Reg
                    escrita_endereco = instrucao_completa[14:11];
                    reg_1_endereco = instrucao_completa[10:7];
                    reg_2_endereco = instrucao_completa[3:0];
                    operador_1 = reg_1_conteudo;
                    operador_2 = reg_2_conteudo;
                end

                OP_ADDI,
                OP_SUBI,
                OP_MUL: begin
                    // Reg x Imm
                    escrita_endereco = instrucao_completa[14:11];
                    reg_1_endereco = instrucao_completa[10:7];
                    operador_1 = reg_1_conteudo;
                    operador_2 = imediato_estendido;
                end

                OP_DISPLAY: begin
                    // Apenas ler
                    reg_1_endereco = instrucao_completa[14:11];
                    escrita_endereco = instrucao_completa[14:11]; // Para mostrar [Reg] no LCD
                    operador_1 = reg_1_conteudo;
                end

                default: begin
                    // NOP / segurança
                end
            endcase
        end
    end

endmodule