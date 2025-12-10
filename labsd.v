module lcd(
    input wire clk,
    input wire rst_n,
    input wire init_done,      
    input wire send_key,       // Botão de envio
    input wire [2:0] opcode,   
    output reg lcd_rs,
    output reg lcd_rw,
    output reg lcd_en,
    output reg [7:0] lcd_data,
    output reg fsm_done
);

    // --- Definição dos Estados ---
    localparam S_WAIT_INIT   = 4'd0;
    localparam S_IDLE        = 4'd1; 
    
    // Estados de Limpeza
    localparam S_CLEAR_SETUP = 4'd2;
    localparam S_CLEAR_PULSE = 4'd3;
    localparam S_CLEAR_WAIT  = 4'd4;
    
    // Estados de Escrita de Texto
    localparam S_DATA_SETUP  = 4'd5;
    localparam S_DATA_PULSE  = 4'd6;
    localparam S_DATA_WAIT   = 4'd7;

    // Estados para Pular para Linha 2 (NOVO)
    localparam S_LINE2_SETUP = 4'd8;
    localparam S_LINE2_PULSE = 4'd9;
    localparam S_LINE2_WAIT  = 4'd10;
    
    reg [3:0] state;

    // --- Parâmetros ---
    localparam TIME_CHAR  = 2500;   // ~50us
    localparam TIME_CLEAR = 100000; // ~2ms

    reg [19:0] delay_cnt;
    reg [5:0]  msg_index; // Aumentado para 6 bits (conta até 63, precisamos de 32)
    
    // --- Buffer de Mensagem (32 caracteres * 8 bits = 256 bits) ---
    // Armazena a mensagem completa que será exibida
    reg [255:0] current_msg; 
    reg [2:0]   latched_opcode;

    // --- Detector de Borda ---
    reg key_prev;
    wire button_released;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) key_prev <= 1;
        else key_prev <= send_key;
    end
    assign button_released = (!key_prev && send_key);

    // --- Lógica de Seleção de Mensagem (Strings Completas) ---
    // Aqui definimos o que aparece na tela (32 chars)
    // Formato: "LINHA 1 (16 chars) LINHA 2 (16 chars)"
    always @(*) begin
        case (latched_opcode) 
            //                        1234567890123456  1234567890123456
            3'b000: current_msg = "LOAD      [xxxx]Carrega Valor   "; 
            3'b001: current_msg = "ADD       [xxxx]Soma Registrador"; 
            3'b010: current_msg = "ADDI      [xxxx]Soma Imediato   "; 
            3'b011: current_msg = "SUB       [xxxx]Subtrai Reg     "; 
            3'b100: current_msg = "SUBI      [xxxx]Subtrai Imediato"; 
            3'b101: current_msg = "MUL       [xxxx]Multiplica      "; 
            3'b110: current_msg = "CLR       [xxxx]Limpa Display   "; 
            3'b111: current_msg = "DPL       [xxxx]Display Line    "; 
            default:current_msg = "UNKNOWN OP      Erro de Selecao ";
        endcase
    end

    // Função auxiliar para pegar o byte certo do vetor gigante
    // Como vetores são indexados [255:0], o char 0 está em [255:248]
    wire [7:0] char_at_index;
    assign char_at_index = current_msg[255 - (msg_index * 8) -: 8];

    // --- FSM Principal ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT_INIT;
            msg_index <= 0;
            delay_cnt <= 0;
            lcd_en <= 0;
            lcd_rs <= 0;
            lcd_rw <= 0;
            fsm_done <= 0;
            latched_opcode <= 0;
        end else begin
            
            case (state)
                S_WAIT_INIT: begin
                    if (init_done) begin
                        fsm_done <= 1; 
                        state <= S_IDLE;
                    end
                end

                S_IDLE: begin
                    fsm_done <= 1; 
                    if (button_released) begin
                        fsm_done <= 0;
                        latched_opcode <= opcode; // Captura Opcode
                        msg_index <= 0;
                        state <= S_CLEAR_SETUP;   // Inicia ciclo
                    end
                end

                // --- 1. LIMPAR TELA ---
                S_CLEAR_SETUP: begin
                    lcd_rs   <= 0; lcd_data <= 8'h01; // CMD Clear
                    delay_cnt <= 0; state <= S_CLEAR_PULSE;
                end
                S_CLEAR_PULSE: begin
                    if (delay_cnt < 20) begin lcd_en <= 1; delay_cnt <= delay_cnt + 1; end
                    else begin lcd_en <= 0; delay_cnt <= 0; state <= S_CLEAR_WAIT; end
                end
                S_CLEAR_WAIT: begin // Espera 2ms
                    if (delay_cnt < TIME_CLEAR) delay_cnt <= delay_cnt + 1;
                    else begin delay_cnt <= 0; state <= S_DATA_SETUP; end
                end

                // --- 2. ESCREVER CARACTERE ---
                S_DATA_SETUP: begin
                    lcd_rs   <= 1; // Dado (Texto)
                    lcd_data <= char_at_index; // Pega letra do vetorzão
                    delay_cnt <= 0;
                    state    <= S_DATA_PULSE;
                end
                S_DATA_PULSE: begin
                    if (delay_cnt < 20) begin lcd_en <= 1; delay_cnt <= delay_cnt + 1; end
                    else begin lcd_en <= 0; delay_cnt <= 0; state <= S_DATA_WAIT; end
                end
                S_DATA_WAIT: begin
                    if (delay_cnt < TIME_CHAR) delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 0;
                        
                        // LÓGICA DE DECISÃO DE FLUXO
                        if (msg_index == 15) begin
                            // Se acabamos de escrever a letra 15 (fim da linha 1)
                            // Precisamos pular para a linha 2
                            msg_index <= msg_index + 1;
                            state <= S_LINE2_SETUP; 
                        end 
                        else if (msg_index < 31) begin
                            // Continua escrevendo
                            msg_index <= msg_index + 1;
                            state <= S_DATA_SETUP;
                        end 
                        else begin
                            // Acabou (32 letras)
                            state <= S_IDLE;
                        end
                    end
                end

                // --- 3. PULAR PARA LINHA 2 (Endereço 0x40) ---
                S_LINE2_SETUP: begin
                    lcd_rs   <= 0;       // Comando
                    lcd_data <= 8'hC0;   // 0x80 (Set Address) + 0x40 (Line 2 Start)
                    delay_cnt <= 0;
                    state    <= S_LINE2_PULSE;
                end
                S_LINE2_PULSE: begin
                    if (delay_cnt < 20) begin lcd_en <= 1; delay_cnt <= delay_cnt + 1; end
                    else begin lcd_en <= 0; delay_cnt <= 0; state <= S_LINE2_WAIT; end
                end
                S_LINE2_WAIT: begin
                    // Esse comando é rápido (como escrever char), espera TIME_CHAR
                    if (delay_cnt < TIME_CHAR) delay_cnt <= delay_cnt + 1;
                    else begin 
                        delay_cnt <= 0; 
                        state <= S_DATA_SETUP; // Volta a escrever o texto (índice 16)
                    end
                end

            endcase
        end
    end
endmodule