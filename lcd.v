module lcd(
    input wire clk,
    input wire reset,       
    input wire sinal_start,
    input wire [2:0] entrada_op,
    input wire [3:0] entrada_end, // endereco do reg para ser exibido
    input wire signed [15:0] entrada_valor,
    output reg [7:0] saida_dados, // saida com o barramento para o lcd(ASCII ou comando(tipo o de limpar a tela)) para subir para os pinos do lcd
    output reg lcd_rs,       // 0 se comando e 1 para texto a ser impresso
    output reg lcd_rw, // sempre 0 para somente escrever
    output reg lcd_e // enable do lcd 0-1-0
);

    reg [2:0] op_salva;
    reg [3:0] end_salvo;
    reg signed [15:0] val_salvo; // esse valor vai ser a "foto" para n 

    localparam [7:0] CMD_SET_FUNC = 8'h38; // 2 linhas e 5x7
    localparam [7:0] CMD_LIGAR    = 8'h0C; // apagar o cursor e nao piscar
    localparam [7:0] CMD_LIMPAR   = 8'h01; // limpa a tela
    localparam [7:0] CMD_MODO     = 8'h06; // move o cursor para a direita a cada escrita de letra

    localparam [31:0] T_INI_LONGO  = 32'd2_500_000; // ao ligar a energia
    localparam [31:0] T_CMD_CURTO  = 32'd2_500; // tempo entre uma letra e outra
    localparam [31:0] T_CMD_LENTO  = 32'd100_000; // o limpar demora mais
    localparam [31:0] T_PULSO      = 32'd50; // tempo do enable

    reg [7:0] lista_cmds [0:3];
    initial begin // seta as configs do lcd
        lista_cmds[0] = CMD_SET_FUNC;
        lista_cmds[1] = CMD_LIGAR;
        lista_cmds[2] = CMD_LIMPAR;
        lista_cmds[3] = CMD_MODO;
    end

    wire [15:0] val_absoluto = (val_salvo < 0) ? -val_salvo : val_salvo; // garante que o numero mandado para o conversor de numero seja positiva, para n dar bugs de exibicao
    wire [3:0] dig_4, dig_3, dig_2, dig_1, dig_0;

    binarioParaBCD conversor ( // a fincao de converter o bcd
        .binario(val_absoluto),
        .dezenaDeMilhar(dig_4), .milhar(dig_3), .centena(dig_2), .dezena(dig_1), .unidade(dig_0)
    );

    reg [7:0] texto_tela [0:31];
    integer k;

    always @(*) begin // esse e um combinacional que altera o valor do print( somente armazena)
	 
        for(k=0; k<32; k=k+1) texto_tela[k] = " "; // essa funcao limpa a os caracteres armazenados
        case (op_salva) // essa só atribui o valor do nome de cada variavel
            3'b000: begin texto_tela[0]="L"; texto_tela[1]="O"; texto_tela[2]="A"; texto_tela[3]="D"; end
            3'b001: begin texto_tela[0]="A"; texto_tela[1]="D"; texto_tela[2]="D"; texto_tela[3]=" "; end
            3'b010: begin texto_tela[0]="A"; texto_tela[1]="D"; texto_tela[2]="D"; texto_tela[3]="I"; end
            3'b011: begin texto_tela[0]="S"; texto_tela[1]="U"; texto_tela[2]="B"; texto_tela[3]=" "; end
            3'b100: begin texto_tela[0]="S"; texto_tela[1]="U"; texto_tela[2]="B"; texto_tela[3]="I"; end
            3'b101: begin texto_tela[0]="M"; texto_tela[1]="U"; texto_tela[2]="L"; texto_tela[3]="T"; end
            3'b110: begin texto_tela[0]="C"; texto_tela[1]="L"; texto_tela[2]="R"; texto_tela[3]=" "; end
            3'b111: begin texto_tela[0]="D"; texto_tela[1]="P"; texto_tela[2]="L"; texto_tela[3]=" "; end
            default:begin texto_tela[0]="E"; texto_tela[1]="R"; texto_tela[2]="R"; texto_tela[3]="O"; end
        endcase
        texto_tela[10] = "[";
        texto_tela[11] = (end_salvo[3]) ? "1" : "0"; // ternario para converter os numeros booleanos para char inteiros
        texto_tela[12] = (end_salvo[2]) ? "1" : "0";
        texto_tela[13] = (end_salvo[1]) ? "1" : "0";
        texto_tela[14] = (end_salvo[0]) ? "1" : "0";
        texto_tela[15] = "]";
        texto_tela[26] = (val_salvo < 0) ? "-" : "+"; // o valor original que foi salvo agr e usado para comparar
        texto_tela[27] = 8'h30 + dig_4; // esse dig vem da funcao de convercao
        texto_tela[28] = 8'h30 + dig_3;
        texto_tela[29] = 8'h30 + dig_2;
        texto_tela[30] = 8'h30 + dig_1;
        texto_tela[31] = 8'h30 + dig_0;
    end

    localparam [3:0]
		 EST_RESET        = 4'b0000, 
		 EST_AGUARDA_BOOT = 4'b0001, 
		 EST_OCIOSO       = 4'b0010, // espera o botao
		 EST_SYNC_CPU     = 4'b0011, // le as entradas
		 EST_PREPARA_BYTE = 4'b0100, // configura os dados e o rs
		 EST_PULSO_E      = 4'b0101, // ativa o enable
		 EST_DELAY_GEN    = 4'b0110, // espera
		 EST_PROXIMO      = 4'b0111, // verifica se o loop acabou 
		 EST_TRAVA_FIM    = 4'b1000; // espera soltar botao
	 
    localparam FASE_INIT = 1'b0; // isso sao so variaveis para deixar o codigo mais legivel
    localparam FASE_MSG  = 1'b1;

    reg [3:0] est_atual, est_prox; // os estados presente e futuro
    reg [31:0] cnt, prox_cnt;
    
    // Variáveis de controle do fluxo
    reg fase_atual, prox_fase;      // 0 = Inicializando, 1 = Escrevendo Msg
    reg [5:0] index, prox_index;    // Contador genérico (serve p/ cmds e chars)
    reg [31:0] delay_alvo, prox_delay_alvo; // Quanto tempo esperar no estado atual
    reg travar_entradas;

    // Registradores temporários para saída
    reg [7:0] temp_dados, prox_temp_dados; // somente para registrar as saidas
    reg temp_rs, prox_temp_rs; 

    // Atualizado para usar 'reset'
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            est_atual  <= EST_RESET;
            cnt        <= 0;
            fase_atual <= FASE_INIT;
            index      <= 0;
            // Zera regs internos
            op_salva   <= 0;
            end_salvo  <= 0;
            val_salvo  <= 0;
            // Zera saidas temporarias
            delay_alvo <= 0;
            temp_dados <= 0;
            temp_rs    <= 0;
        end
        else begin
            est_atual       <= est_prox;
            cnt             <= prox_cnt;
            fase_atual      <= prox_fase;
            index           <= prox_index;
            delay_alvo      <= prox_delay_alvo;
            temp_dados      <= prox_temp_dados;
            temp_rs         <= prox_temp_rs;

            if (travar_entradas) begin
                op_salva  <= entrada_op;
                end_salvo <= entrada_end;
                val_salvo <= entrada_valor;
            end
        end
    end

    always @(*) begin
        // Defaults
        est_prox        = est_atual;
        prox_cnt        = cnt;
        prox_fase       = fase_atual;
        prox_index      = index;
        prox_delay_alvo = delay_alvo;
        prox_temp_dados = temp_dados;
        prox_temp_rs    = temp_rs;
        travar_entradas = 0;

        case(est_atual)
            EST_RESET: begin
                prox_cnt = 0;
                est_prox = EST_AGUARDA_BOOT;
            end

            // 1. Espera inicial de energia (15ms+)
            EST_AGUARDA_BOOT: begin
                if (cnt < T_INI_LONGO)
                    prox_cnt = cnt + 1;
                else begin
                    prox_cnt   = 0;
                    prox_fase  = FASE_INIT;
                    prox_index = 0; 
                    est_prox   = EST_PREPARA_BYTE; // Vai mandar comandos de init
                end
            end

            // 2. Estado Ocioso (Só chega aqui após terminar INIT)
            EST_OCIOSO: begin
                if (sinal_start) begin
                    prox_cnt = 0;
                    est_prox = EST_SYNC_CPU;
                end
            end

            // 3. Captura dados da CPU
            EST_SYNC_CPU: begin
                if (cnt < 32'd1000)
                    prox_cnt = cnt + 1;
                else begin
                    travar_entradas = 1; // LATCH
                    prox_fase       = FASE_MSG;
                    prox_index      = 0;
                    est_prox        = EST_PREPARA_BYTE;
                end
            end

            // 4. CEREBRO CENTRAL: Decide qual byte enviar agora
            EST_PREPARA_BYTE: begin
                prox_cnt = 0; // Prepara contador pro delay futuro
                
                if (fase_atual == FASE_INIT) begin
                    // --- MODO INICIALIZAÇÃO (4 Comandos) ---
                    prox_temp_rs    = 0;
                    prox_temp_dados = lista_cmds[index[1:0]];
                    prox_delay_alvo = (index == 2) ? T_CMD_LENTO : T_CMD_CURTO;
                    est_prox        = EST_PULSO_E;
                end
                else begin
                    
                    if (index == 0) begin // Configura Linha 1
                        prox_temp_rs = 0; 
                        prox_temp_dados = 8'h80; 
                        prox_delay_alvo = T_CMD_CURTO;
                        est_prox = EST_PULSO_E;
                    end
                    else if (index == 17) begin // Configura Linha 2
                        prox_temp_rs = 0; 
                        prox_temp_dados = 8'hC0;
                        prox_delay_alvo = T_CMD_CURTO;
                        est_prox = EST_PULSO_E;
                    end
                    else begin // É caractere
                        prox_temp_rs = 1;
                        // Ajusta indice para ler vetor 0-31 corretamente
                        if (index < 17)
                            prox_temp_dados = texto_tela[index - 1];
                        else
                            prox_temp_dados = texto_tela[index - 2];
                            
                        prox_delay_alvo = T_CMD_CURTO;
                        est_prox = EST_PULSO_E;
                    end
                end
            end

            // 5. Gera o Pulso de Enable
            EST_PULSO_E: begin
                if (cnt < T_PULSO)
                    prox_cnt = cnt + 1;
                else begin
                    prox_cnt = 0;
                    est_prox = EST_DELAY_GEN;
                end
            end

            // 6. Espera o tempo definido em delay_alvo
            EST_DELAY_GEN: begin
                if (cnt < delay_alvo)
                    prox_cnt = cnt + 1;
                else
                    est_prox = EST_PROXIMO;
            end

            // 7. Decide o próximo passo
            EST_PROXIMO: begin
                if (fase_atual == FASE_INIT) begin
                    if (index < 3) begin
                        prox_index = index + 1;
                        est_prox   = EST_PREPARA_BYTE;
                    end else begin
                        est_prox   = EST_OCIOSO;
                    end
                end
                else begin // FASE_MSG
                    if (index < 33) begin
                        prox_index = index + 1;
                        est_prox   = EST_PREPARA_BYTE;
                    end else begin
                        est_prox   = EST_TRAVA_FIM; // Acabou msg
                    end
                end
            end

            // 8. Só libera se soltar o botão
            EST_TRAVA_FIM: begin
                if (!sinal_start)
                    est_prox = EST_OCIOSO;
            end
            
            default: est_prox = EST_RESET;
        endcase
    end

    always @(*) begin // combinacional para atribuir as saidas
        lcd_e       = 0;
        lcd_rw      = 0;
        lcd_rs      = temp_rs;     // Segue o que esta na na FSM
        saida_dados = temp_dados;  

        if (est_atual == EST_PULSO_E) // se o estado for de enviar ele lanca o enable para o lcd exibir o texto
            lcd_e = 1;
    end

endmodule