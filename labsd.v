module lcd(
    input wire clk,
    input wire rst_n,
    input wire init_done,      // Vem da FSM de inicialização
    input wire send_key,       // NOVO: Conectar a um KEY (ex: KEY[1])
    input wire [2:0] opcode,   // Switches SW[17:15]
    output reg lcd_rs,
    output reg lcd_rw,
    output reg lcd_en,
    output reg [7:0] lcd_data,
    output reg fsm_done
);

    // --- Definição dos Estados ---
    localparam S_WAIT_INIT   = 4'd0;
    localparam S_IDLE        = 4'd1; // Estado de espera pelo botão
    
    // Estados de Limpeza (Clear)
    localparam S_CLEAR_SETUP = 4'd2;
    localparam S_CLEAR_PULSE = 4'd3;
    localparam S_CLEAR_WAIT  = 4'd4;
    
    // Estados de Escrita (Write)
    localparam S_DATA_SETUP  = 4'd5;
    localparam S_DATA_PULSE  = 4'd6;
    localparam S_DATA_WAIT   = 4'd7;
    
    reg [3:0] state;

    // --- Parâmetros de Tempo (Clock 50MHz) ---
    localparam TIME_CHAR  = 2500;   // ~50us
    localparam TIME_CLEAR = 100000; // ~2ms

    reg [19:0] delay_cnt;
    reg [3:0]  msg_index;
    
    // Registrador para "congelar" o valor dos switches quando apertar o botão
    reg [2:0]  latched_opcode; 

    // --- DETECTOR DE BORDA DO BOTÃO ---
    reg key_prev;
    wire button_released;
    
    // Detecta a transição 0 -> 1 (Soltou o botão)
    // Na DE2-115: Pressionado = 0, Solto = 1.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) key_prev <= 1;
        else key_prev <= send_key;
    end
    
    // O pulso acontece APENAS no ciclo exato onde ele foi solto
    assign button_released = (!key_prev && send_key);

    // --- MUX de Caracteres ---
    reg [7:0] char_to_send;
    // Nota: Agora usamos 'latched_opcode' em vez de 'opcode' direto
    // para garantir que o texto não mude no meio da escrita se vc mexer na chave.
    always @(*) begin
        char_to_send = 8'h20; 
        case (latched_opcode)
            3'b000: begin // LOAD
                if (msg_index == 0) char_to_send = "L";
                else if (msg_index == 1) char_to_send = "O";
                else if (msg_index == 2) char_to_send = "A";
                else if (msg_index == 3) char_to_send = "D";
            end
            3'b001: begin // ADD
                if (msg_index == 0) char_to_send = "A";
                else if (msg_index == 1) char_to_send = "D";
                else if (msg_index == 2) char_to_send = "D";
                else if (msg_index == 3) char_to_send = " ";
            end
            3'b010: begin // ADDI
                if (msg_index == 0) char_to_send = "A";
                else if (msg_index == 1) char_to_send = "D";
                else if (msg_index == 2) char_to_send = "D";
                else if (msg_index == 3) char_to_send = "I";
            end
            3'b011: begin // SUB
                if (msg_index == 0) char_to_send = "S";
                else if (msg_index == 1) char_to_send = "U";
                else if (msg_index == 2) char_to_send = "B";
                else if (msg_index == 3) char_to_send = " ";
            end
            3'b100: begin // SUBI
                if (msg_index == 0) char_to_send = "S";
                else if (msg_index == 1) char_to_send = "U";
                else if (msg_index == 2) char_to_send = "B";
                else if (msg_index == 3) char_to_send = "I";
            end
            3'b101: begin // MUL
                if (msg_index == 0) char_to_send = "M";
                else if (msg_index == 1) char_to_send = "U";
                else if (msg_index == 2) char_to_send = "L";
                else if (msg_index == 3) char_to_send = " ";
            end
            3'b110: begin // CLR
                if (msg_index == 0) char_to_send = "C";
                else if (msg_index == 1) char_to_send = "L";
                else if (msg_index == 2) char_to_send = "R";
                else if (msg_index == 3) char_to_send = " ";
            end
            3'b111: begin // DPL
                if (msg_index == 0) char_to_send = "D";
                else if (msg_index == 1) char_to_send = "P";
                else if (msg_index == 2) char_to_send = "L";
                else if (msg_index == 3) char_to_send = " ";
            end
        endcase
    end

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
            latched_opcode <= 3'b000;
        end else begin
            
            case (state)
                // 1. Espera Inicialização
                S_WAIT_INIT: begin
                    if (init_done) begin
                        // Ao iniciar, já carrega o valor atual e imprime uma vez (opcional)
                        // Ou vai direto para IDLE esperar o botão. Vamos para IDLE.
                        fsm_done <= 1; 
                        state <= S_IDLE;
                    end
                end

                // 2. Estado de Espera (Aguarda você soltar o botão)
                S_IDLE: begin
                    fsm_done <= 1; // Indica que está pronto/parado
                    
                    if (button_released) begin
                        // O evento aconteceu!
                        fsm_done <= 0;
                        latched_opcode <= opcode; // Captura a posição das chaves AGORA
                        msg_index <= 0;
                        state <= S_CLEAR_SETUP;   // Inicia processo de limpeza e escrita
                    end
                end

                // --- PROCESSO DE LIMPEZA ---
                S_CLEAR_SETUP: begin
                    lcd_rs   <= 0;       // Comando
                    lcd_data <= 8'h01;   // Clear Display
                    delay_cnt <= 0;
                    state    <= S_CLEAR_PULSE;
                end

                S_CLEAR_PULSE: begin
                    if (delay_cnt < 20) begin
                        lcd_en <= 1;
                        delay_cnt <= delay_cnt + 1;
                    end else begin
                        lcd_en <= 0;
                        delay_cnt <= 0;
                        state <= S_CLEAR_WAIT;
                    end
                end

                S_CLEAR_WAIT: begin
                    if (delay_cnt < TIME_CLEAR) delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 0;
                        state <= S_DATA_SETUP;
                    end
                end

                // --- PROCESSO DE ESCRITA ---
                S_DATA_SETUP: begin
                    lcd_rs   <= 1;            // Dado
                    lcd_data <= char_to_send; // Usa latched_opcode
                    delay_cnt <= 0;
                    state    <= S_DATA_PULSE;
                end

                S_DATA_PULSE: begin
                    if (delay_cnt < 20) begin
                        lcd_en <= 1;
                        delay_cnt <= delay_cnt + 1;
                    end else begin
                        lcd_en <= 0;
                        delay_cnt <= 0;
                        state <= S_DATA_WAIT;
                    end
                end

                S_DATA_WAIT: begin
                    if (delay_cnt < TIME_CHAR) delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 0;
                        msg_index <= msg_index + 1;
                        
                        if (msg_index < 3) state <= S_DATA_SETUP;
                        else state <= S_IDLE; // Volta a esperar o botão
                    end
                end
            endcase
        end
    end

endmodule