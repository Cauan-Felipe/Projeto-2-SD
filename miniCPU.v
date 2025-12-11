module module_mini_cpu (
    input wire CLOCK_50,        // Clock da placa (50MHz)
    input wire [17:0] SW,       // Switches para instrução
    input wire [3:0] KEY,       // KEY[0] = Reset, KEY[1] = Enviar
    
    // Saídas para o LCD (físico na placa)
    output wire LCD_RS,
    output wire LCD_RW,
    output wire LCD_EN,
    output wire [7:0] LCD_DATA,
    output wire LCD_ON,
    output wire LCD_BLON,
    
    // Debug (Opcional: LEDs para ver o estado)
    output wire [17:0] LEDR,
    output wire [7:0] LEDG
);

    // --- 1. Sinais de Controle e Tratamento de Botões ---
    wire rst_n = KEY[0];     // Reset ativo baixo
    wire send_key = KEY[1];  // Botão de envio (ativo baixo)

    // Detector de borda de subida para o botão de envio (Write Enable da RAM)
    // A memória só escreve quando soltamos o botão, assim como o LCD inicia.
    reg key_prev;
    wire button_released;
    
    always @(posedge CLOCK_50) begin
        key_prev <= send_key;
    end
    // Detecta transição de 0 (pressionado) para 1 (solto)
    assign button_released = (!key_prev && send_key);


    // --- 2. Decodificação de Instruções (O Cérebro) ---
    // O PDF define posições diferentes para o Opcode. Vamos "sondar" todas.
    
    wire [2:0] op_type_2 = SW[17:15]; // ADDI, SUBI, MUL
    wire [2:0] op_type_1 = SW[14:12]; // ADD, SUB
    wire [2:0] op_type_3 = SW[13:11]; // LOAD
    wire [2:0] op_type_4 = SW[7:5];   // DISPLAY, CLEAR (Usando 3 bits mais altos)

    reg [2:0] final_opcode;
    reg [3:0] dest, src1, src2;
    reg [15:0] imm_value;
    reg use_imm;      // 1 se a instrução usa imediato, 0 se usa registrador
    reg mem_write_en; // 1 se a instrução escreve na memória

    always @(*) begin
        // Padrão: zera tudo para evitar latch
        final_opcode = 3'b000;
        dest = 4'd0; src1 = 4'd0; src2 = 4'd0;
        imm_value = 16'd0;
        use_imm = 0;
        mem_write_en = 0;

        // Lógica de Prioridade para descobrir a instrução
        // Baseado na tabela de Opcodes do PDF [cite: 94]
        
        if (op_type_2 == 3'b010 || op_type_2 == 3'b100 || op_type_2 == 3'b101) begin
            // --- TIPO 2: ADDI (010), SUBI (100), MUL (101) --- [cite: 118]
            final_opcode = op_type_2;
            dest = SW[14:11];
            src1 = SW[10:7];
            // O Imediato tem sinal (bit 6) e valor (5:0). Extensão de sinal para 16 bits:
            imm_value = {{9{SW[6]}}, SW[6:0]}; 
            use_imm = 1;
            mem_write_en = 1; // Essas instruções escrevem resultado
        end
        else if (op_type_1 == 3'b001 || op_type_1 == 3'b011) begin
            // --- TIPO 1: ADD (001), SUB (011) --- [cite: 103]
            final_opcode = op_type_1;
            dest = SW[11:8];
            src1 = SW[7:4];
            src2 = SW[3:0];
            use_imm = 0;
            mem_write_en = 1;
        end
        else if (op_type_3 == 3'b000) begin
            // --- TIPO 3: LOAD (000) --- [cite: 123]
            final_opcode = 3'b000;
            dest = SW[10:7];
            // Imediato do LOAD: Bit 6 sinal, 5:0 valor
            imm_value = {{9{SW[6]}}, SW[6:0]};
            use_imm = 1; // LOAD tecnicamente usa um imediato para passar pela ULA
            mem_write_en = 1;
        end
        else if (op_type_4 == 3'b111 || op_type_4 == 3'b110) begin
            // --- TIPO 4: DISPLAY (111) ou CLEAR (110) --- [cite: 134]
            // Nota: O PDF diz [7:4], mas opcode é 3 bits. Assumindo bits superiores.
            final_opcode = op_type_4; 
            dest = SW[3:0]; // Para Display, o registrador alvo fica aqui
            mem_write_en = 0; // Display e Clear NÃO escrevem na memória (exceto reset do clear)
        end
    end

    // --- 3. Instanciação da Memória ---
    wire [15:0] r_data1, r_data2;
    wire [15:0] w_data; // Dado que será escrito (vem da ULA)
    
    // O sinal de escrita só pulsa quando o botão é solto E a instrução permite escrita
    wire write_enable_pulse = button_released && mem_write_en;
    
    // Implementar CLEAR: Se opcode for 110 (CLEAR), ativamos o reset da memória?
    // Ou podemos criar uma lógica específica. Vamos usar o Reset global por enquanto
    // ou adicionar lógica extra. O PDF diz que CLEAR zera os registradores[cite: 128].
    wire clear_cmd = (final_opcode == 3'b110 && button_released);
    wire global_reset_mem = (!rst_n) || clear_cmd; 

    memory RAM (
        .clk(CLOCK_50),
        .reset(global_reset_mem), 
        .Dest(dest),
        .WriteData(w_data),
        .RegWrite(write_enable_pulse),
        .Src1(src1),
        .Src2(use_imm ? 4'd0 : src2), // Se for imediato, Src2 não importa (mas ULA precisa de B)
        .ReadData1(r_data1),
        .ReadData2(r_data2)
    );

    // --- 4. Preparação para a ULA ---
    // MUX para decidir se a entrada B da ULA vem do Reg2 ou do Imediato
    wire [15:0] alu_in_B = (use_imm) ? imm_value : r_data2;
    
    // No caso do LOAD, queremos apenas passar o Imediato para a Saída.
    // Nossa ULA soma (000 não faz nada no default). 
    // Truque: Para LOAD, podemos fazer "0 + Imediato".
    // Ou garantir que a ULA tenha uma operação "Pass B".
    // Vamos assumir que LOAD (000) na sua ULA caia no default ou seja tratado.
    // Sugestão: Altere sua ULA para tratar op 000 como "S = B".
    
    // Instância da ULA
    module_alu ALU (
        .A(r_data1),    // Sempre vem do Registrador 1 (exceto LOAD que ignora A)
        .B(alu_in_B),   // Vem do Reg 2 ou Imediato
        .opcode(final_opcode),
        .S(w_data)      // O resultado vai para a porta de escrita da memória
    );

    // --- 5. Integração com o LCD ---
    // Gerador de sinal de Init fake (pois não temos o controlador externo aqui)
    reg [20:0] init_cnt;
    reg lcd_init_done;
    always @(posedge CLOCK_50) begin
        if (!rst_n) begin init_cnt <= 0; lcd_init_done <= 0; end
        else if (init_cnt < 1000000) init_cnt <= init_cnt + 1; // Espera um pouco
        else lcd_init_done <= 1;
    end

    // Instância do módulo LCD que você forneceu
    // IMPORTANTE: O LCD receberá o Opcode para escrever o texto base.
    // Futuramente, precisaremos passar 'w_data' para ele exibir o número.
    lcd DISPLAY (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .init_done(lcd_init_done),
        .send_key(send_key),    // O LCD tem a própria detecção de botão
        .opcode(final_opcode),  // Manda o opcode decodificado
        .lcd_rs(LCD_RS),
        .lcd_rw(LCD_RW),
        .lcd_en(LCD_EN),
        .lcd_data(LCD_DATA),
        .fsm_done() // Não usado por enquanto
    );

    // Ligar o Backlight e Display do hardware
    assign LCD_ON = 1'b1;
    assign LCD_BLON = 1'b1;
    
    // Debug nos LEDs
    assign LEDG[7:5] = final_opcode;
    assign LEDR[15:0] = w_data; // Mostra o resultado da ULA nos LEDs vermelhos

endmodule
