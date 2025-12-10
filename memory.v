// module_memory.v
// Implementa o Banco de Registradores (Register File) 16x16 bits

module memory (
    // Clock e Reset
    input wire clk,             // Clock principal
    input wire reset,           // Sinal de Reset Assíncrono para zerar tudo [cite: 6, 65]
    
    // Entradas para Escrita (Write)
    input wire [3:0] Dest,      // Endereço de 4 bits do Registrador de Destino (R0 a R15)
    input wire [15:0] WriteData, // Dado de 16 bits a ser escrito
    input wire RegWrite,        // Habilita a escrita no registrador
    
    // Entradas para Leitura (Read)
    input wire [3:0] Src1,      // Endereço de 4 bits do Registrador Fonte 1
    input wire [3:0] Src2,      // Endereço de 4 bits do Registrador Fonte 2
    
    // Saídas de Leitura
    output wire [15:0] ReadData1, // Dado de 16 bits lido de Src1
    output wire [15:0] ReadData2  // Dado de 16 bits lido de Src2
);

    // Declaração do Banco de Registradores
    // reg_file [15:0] => 16 posições de 16 bits [cite: 179]
    reg [15:0] reg_file [0:15];
    
    // --- 1. Inicialização e Escrita no Banco de Registradores ---
    
    // Blocos Always @ (posedge clk or posedge reset) são ideais para circuitos sequenciais.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Lógica de Reset Assíncrono: Zera todos os 16 registradores [cite: 6, 65, 179]
            // Também usado pela instrução CLEAR [cite: 127]
            integer i;
            for (i = 0; i < 16; i = i + 1) begin
                reg_file[i] <= 16'h0000;
            end
        end else if (RegWrite) begin
            // Executa a Escrita Síncrona (na borda de subida do clock)
            // O dado (WriteData) é armazenado no endereço (Dest) se RegWrite for 1.
            // Garantir que R0 não seja escrito é uma boa prática, mas
            // o requisito é apenas para 16 registradores gerais[cite: 179].
            reg_file[Dest] <= WriteData;
        end
    end
    
    // --- 2. Leitura do Banco de Registradores ---
    
    // Leitura é Combinacional (assíncrona ao clock) para que o dado esteja
    // disponível imediatamente após o endereço (Src1/Src2) mudar.
    
    // Atribuição de Saída 1
    assign ReadData1 = reg_file[Src1];
    
    // Atribuição de Saída 2
    assign ReadData2 = reg_file[Src2];

endmodule