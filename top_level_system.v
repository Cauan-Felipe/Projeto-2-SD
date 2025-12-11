// ============================================================================
// MÓDULO TOP LEVEL (Integração: Memória + ALU + LCD)
// ============================================================================
module top_level_system (
    input CLOCK_50,             // Clock de 50MHz da placa DE2-115
    input [17:0] SW,            // Switches para controle e dados
    input [3:0] KEY,            // Botões (Push-buttons)
    
    output [17:0] LEDR,         // LEDs Vermelhos (Visualização de dados)
    output [8:0] LEDG,          // LEDs Verdes (Status)

    // --- Interface Física do LCD (Conforme Manual DE2-115) ---
    output [7:0] LCD_DATA,      // Pinos de Dados [7:0]
    output LCD_RW,              // Read/Write Select
    output LCD_EN,              // Enable Pulse
    output LCD_RS,              // Register Select (Command/Data)
    output LCD_ON,              // Power ON
    output LCD_BLON             // Backlight ON
);

    // --- 1. Sinais de Controle Globais ---
    wire clk = CLOCK_50;
    wire reset = ~KEY[0];        // Reset global (KEY0 invertida)
    wire write_enable = ~KEY[1]; // Botão de escrita na memória (KEY1 invertida)

    // --- 2. Fios de Interconexão (Wires) ---
    
    // Sinais da Memória
    wire [15:0] mem_out_A;       // Dado lido de Src1
    wire [15:0] mem_out_B;       // Dado lido de Src2
    wire [15:0] mem_in_data;     // Dado a ser escrito na memória
    wire [3:0]  addr_dest = SW[7:4];   // Endereço de Destino (Bits 7-4)
    wire [3:0]  addr_src1 = SW[7:4];   // Endereço Fonte 1 (Bits 7-4)
    wire [3:0]  addr_src2 = SW[11:8];  // Endereço Fonte 2 (Bits 11-8)

    // Sinais da ALU
    wire [16:0] alu_result;      // Resultado da operação (16 bits + 1 carry)
    wire [2:0]  alu_opcode = SW[2:0]; // Opcode da operação (Bits 2-0)

    // Sinais do LCD
    wire [15:0] lcd_value_to_show; // Qual dado vai aparecer na tela
    wire start_lcd_update;         // Pulso para atualizar a tela

    // --- 3. Lógica de Seleção de Dados (Multiplexadores) ---

    // MUX DE ESCRITA NA MEMÓRIA:
    // Se SW[17] = 0 (Modo Manual): Escreve o valor dos Switches [15:8]
    // Se SW[17] = 1 (Modo ALU):    Escreve o resultado da ALU
    assign mem_in_data = (SW[17] == 1'b0) ? {8'h00, SW[15:8]} : alu_result[15:0];

    // MUX DE VISUALIZAÇÃO NO LCD:
    // Se SW[16] ON -> Mostra o operando B (lido da memória)
    // Se SW[15] ON -> Mostra o operando A (lido da memória)
    // Padrão       -> Mostra o Resultado da ALU (S)
    assign lcd_value_to_show = (SW[16]) ? mem_out_B : 
                               (SW[15]) ? mem_out_A : 
                               alu_result[15:0];

    // --- 4. Instanciação do Módulo MEMORY ---
    memory u_memory (
        .clk(clk),
        .reset(reset),
        // Leitura
        .Src1(addr_src1),
        .Src2(addr_src2),
        .ReadData1(mem_out_A),
        .ReadData2(mem_out_B),
        // Escrita
        .Dest(addr_dest),
        .WriteData(mem_in_data),
        .RegWrite(write_enable)
    );

    // --- 5. Instanciação do Módulo ALU ---
    alu u_alu (
        .A(mem_out_A),
        .B(mem_out_B),
        .param(alu_opcode),
        .S(alu_result)  // Nota: Verifique se sua ALU solta 16 ou 17 bits
    );

    // --- 6. Gerador de "Heartbeat" para o LCD ---
    // Cria um pulso a cada ~160ms para atualizar a tela automaticamente
    reg [22:0] timer;
    always @(posedge clk) timer <= timer + 1;
    assign start_lcd_update = (timer == 0); // Pulso quando o contador zera

    // --- 7. Instanciação do Módulo LCD CONTROLLER ---
    lcd_controller u_lcd (
        .clk(clk),
        .reset(reset),
        .start(start_lcd_update), // Atualiza periodicamente
        .data_in(lcd_value_to_show), // O dado selecionado pelo MUX acima
        
        // Conexões Físicas
        .LCD_DATA(LCD_DATA),
        .LCD_RS(LCD_RS),
        .LCD_EN(LCD_EN),
        .LCD_RW(LCD_RW),
        .LCD_ON(LCD_ON),
        .LCD_BLON(LCD_BLON),
        .busy() // Saída busy desconectada (não precisamos monitorar aqui)
    );

    // --- 8. Saídas para LEDs (Debug Visual) ---
    // LEDs Vermelhos: Mostram o dado sendo escrito ou o resultado
    assign LEDR[15:0] = mem_in_data; 
    assign LEDR[16]   = alu_result[16]; // Overflow/Carry
    assign LEDR[17]   = SW[17];         // Indica o modo (Manual ou ALU)

    // LEDs Verdes: Status
    assign LEDG[0] = reset;          // Aceso se estiver em Reset
    assign LEDG[1] = write_enable;   // Pisca quando aperta KEY1
    assign LEDG[2] = SW[15];         // Indica que está vendo Entrada A no LCD
    assign LEDG[3] = SW[16];         // Indica que está vendo Entrada B no LCD

endmodule