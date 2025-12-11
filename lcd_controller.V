module lcd_controller (
    // --- Entradas do Sistema ---
    input wire clk,             // Clock de 50MHz
    input wire reset,           // Reset do sistema
    input wire start,           // Pulso para iniciar a atualização da tela
    input wire [15:0] data_in,  // O dado binário (A, B ou S) para mostrar

    // --- Saídas Físicas (Conforme Imagem 2 - Pin Planner) ---
    output reg [7:0] LCD_DATA,  // LCD_DATA[7:0]
    output reg LCD_RS,          // 0=Comando, 1=Dado (Escrever Caractere)
    output reg LCD_EN,          // Pulso de Enable
    output wire LCD_RW,         // 0=Write (Sempre 0)
    output wire LCD_ON,         // Ligar controlador (Sempre 1)
    output wire LCD_BLON,       // Ligar luz de fundo (Sempre 1)
    
    output reg busy             // 1 = Ocupado, 0 = Pronto
);

    // Configurações Fixas
    assign LCD_RW   = 1'b0; // Sempre escrita
    assign LCD_ON   = 1'b1; // Power ON
    assign LCD_BLON = 1'b1; // Backlight ON

    // --- Parâmetros de Tempo (Para Clock 50MHz) ---
    // O LCD é lento. Precisamos esperar entre comandos.
    parameter TIME_CHAR  = 2500;   // ~50us (Comandos rápidos e dados)
    parameter TIME_CLEAR = 100000; // ~2ms (Comando Clear é lento!)
    
    // --- Comandos Hexadecimais (Baseado na Imagem 1) ---
    // Function Set: DL=1(8bits), N=1(2linhas), F=0(5x7) -> 0011 1000
    localparam CMD_FUNC_SET   = 8'h38; 
    // Display Control: D=1(On), C=0(No Cursor), B=0(No Blink) -> 0000 1100
    localparam CMD_DISP_ON    = 8'h0C; 
    // Clear Display: -> 0000 0001
    localparam CMD_CLEAR      = 8'h01; 
    // Entry Mode: I/D=1(Incrementa), S=0(No Shift) -> 0000 0110
    localparam CMD_ENTRY_MODE = 8'h06; 

    // --- Máquina de Estados ---
    reg [3:0] state;
    localparam S_IDLE       = 0;
    localparam S_INIT_FUNC  = 1;
    localparam S_INIT_DISP  = 2;
    localparam S_INIT_CLEAR = 3;
    localparam S_INIT_ENTRY = 4;
    localparam S_WRITE_D4   = 5; // Dígito [15:12]
    localparam S_WRITE_D3   = 6; // Dígito [11:8]
    localparam S_WRITE_D2   = 7; // Dígito [7:4]
    localparam S_WRITE_D1   = 8; // Dígito [3:0]
    localparam S_WAIT       = 9;

    reg [3:0] next_state_after_wait;
    reg [19:0] counter;
    reg [19:0] delay_target;
    reg [15:0] latched_data;

    // --- Função de Conversão: 4 bits Hex -> 8 bits ASCII ---
    function [7:0] hex2ascii;
        input [3:0] nibble;
        begin
            // Se for 0-9, soma 0x30. Se for A-F, soma 0x37.
            hex2ascii = (nibble < 10) ? (nibble + 8'h30) : (nibble + 8'h37);
        end
    endfunction

    // --- Lógica Sequencial ---
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= S_IDLE;
            LCD_EN <= 0;
            busy <= 0;
            counter <= 0;
            LCD_RS <= 0;
            LCD_DATA <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    busy <= 0;
                    LCD_EN <= 0;
                    if (start) begin
                        busy <= 1;
                        latched_data <= data_in; // Salva o valor para não mudar durante a escrita
                        state <= S_INIT_FUNC;
                    end
                end

                // --- Inicialização (Comandos da Tabela) ---
                S_INIT_FUNC: begin
                    LCD_RS <= 0; // RS=0 (Comando)
                    LCD_DATA <= CMD_FUNC_SET;
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_INIT_DISP;
                    state <= S_WAIT;
                end
                
                S_INIT_DISP: begin
                    LCD_RS <= 0;
                    LCD_DATA <= CMD_DISP_ON;
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_INIT_CLEAR;
                    state <= S_WAIT;
                end

                S_INIT_CLEAR: begin
                    LCD_RS <= 0;
                    LCD_DATA <= CMD_CLEAR;
                    delay_target <= TIME_CLEAR; // Este precisa de mais tempo!
                    next_state_after_wait <= S_INIT_ENTRY;
                    state <= S_WAIT;
                end

                S_INIT_ENTRY: begin
                    LCD_RS <= 0;
                    LCD_DATA <= CMD_ENTRY_MODE;
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_WRITE_D4;
                    state <= S_WAIT;
                end

                // --- Escrita dos Dados (RS=1) com Conversão Interna ---
                S_WRITE_D4: begin
                    LCD_RS <= 1; // RS=1 (Escrever Caractere)
                    LCD_DATA <= hex2ascii(latched_data[15:12]); // Converte bits 15-12
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_WRITE_D3;
                    state <= S_WAIT;
                end

                S_WRITE_D3: begin
                    LCD_RS <= 1;
                    LCD_DATA <= hex2ascii(latched_data[11:8]); // Converte bits 11-8
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_WRITE_D2;
                    state <= S_WAIT;
                end

                S_WRITE_D2: begin
                    LCD_RS <= 1;
                    LCD_DATA <= hex2ascii(latched_data[7:4]); // Converte bits 7-4
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_WRITE_D1;
                    state <= S_WAIT;
                end

                S_WRITE_D1: begin
                    LCD_RS <= 1;
                    LCD_DATA <= hex2ascii(latched_data[3:0]); // Converte bits 3-0
                    delay_target <= TIME_CHAR;
                    next_state_after_wait <= S_IDLE; // Fim!
                    state <= S_WAIT;
                end

                // --- Estado de Espera (Gera o pulso EN) ---
                S_WAIT: begin
                    counter <= counter + 1;
                    
                    // Lógica do pulso EN: Sobe no ciclo 20, desce no ciclo 1000
                    // Isso garante que o DATA esteja estável antes e depois do pulso.
                    if (counter == 20)  LCD_EN <= 1;
                    if (counter == 1000) LCD_EN <= 0;

                    if (counter >= delay_target) begin
                        counter <= 0;
                        state <= next_state_after_wait;
                    end
                end
            endcase
        end
    end
endmodule