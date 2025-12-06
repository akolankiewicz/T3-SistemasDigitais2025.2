/*
 * Elevador com limite de peso
 */

module elevador_pequeno (
    input CLOCK_50,
    input [3:0] KEY,
    input [9:0] SW,
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [9:0] LEDR,
    output [7:0] LEDG
);

    localparam IDLE = 2'b00, UP = 2'b01, DOWN = 2'b10;
    
    reg [1:0] state = IDLE;
    reg [2:0] floor = 3'd1;
    reg [4:0] calls = 5'b0;
    reg [1:0] people = 2'b0;  // 0 a 3 pessoas
    reg emergency_mode = 1'b0;  // Modo emergência
    reg [4:0] unlocked_floors = 5'b11111;  // Andares desbloqueados (1=desbloqueado, 0=bloqueado)
    reg key0_prev, sw9_prev, sw8_prev;
    
    // Controle de standby
    reg [9:0] sw_prev_all = 10'b0;  // Todos os switches anteriores
    reg [3:0] key_prev_all = 4'b0;  // Todos os botões anteriores
    reg [27:0] inactivity_counter = 0;  // Contador de inatividade (5 segundos = 250M ciclos)
    reg standby_mode = 1'b0;  // Modo standby
    localparam INACTIVITY_TIMEOUT = 28'd150000000;  // 3 segundos a 50MHz
    
    always @(posedge CLOCK_50) begin
        key0_prev <= ~KEY[0];
        sw9_prev <= SW[9];
        sw8_prev <= SW[8];
        
        // Detecção de inatividade para modo standby
        sw_prev_all <= SW;
        key_prev_all <= KEY;
    end
    
    // Detecta qualquer mudança nos switches ou botões (fora do bloco always)
    wire activity = (SW != sw_prev_all) || (KEY != key_prev_all);
    
    always @(posedge CLOCK_50) begin
        if (activity) begin
            // Reset do contador de inatividade quando há atividade
            inactivity_counter <= 0;
            standby_mode <= 1'b0;  // Sai do modo standby
        end else if (state == IDLE && !emergency_mode) begin
            // Só conta inatividade quando o elevador estiver parado (IDLE) e não em emergência
            if (inactivity_counter < INACTIVITY_TIMEOUT) begin
                inactivity_counter <= inactivity_counter + 1'b1;
            end else begin
                // Entrou em modo standby após 3 segundos parado sem atividade
                standby_mode <= 1'b1;
            end
        end else begin
            // Se estiver em movimento, reseta o contador
            inactivity_counter <= 0;
        end
    end
    
    wire emergency_pressed = ~key0_prev && ~KEY[0];  // Detecta borda de descida do KEY[0]
    wire add_person = ~sw9_prev && SW[9];
    wire rem_person = ~sw8_prev && SW[8];
    wire is_full = (people == 2'd3);
    wire [4:0] sw_calls = SW[4:0];
    wire [2:0] blocked_floor_sw = SW[7:5];  // Switches SW[7:5] representam o andar bloqueado em binário
    
    // Verifica se há chamadas acima ou abaixo do andar atual
    wire has_call_above = ((floor < 3'd5) && calls[4] && unlocked_floors[4]) ||
                          ((floor < 3'd4) && calls[3] && unlocked_floors[3]) ||
                          ((floor < 3'd3) && calls[2] && unlocked_floors[2]) ||
                          ((floor < 3'd2) && calls[1] && unlocked_floors[1]);
    
    wire has_call_below = ((floor > 3'd1) && calls[0] && unlocked_floors[0]) ||
                          ((floor > 3'd2) && calls[1] && unlocked_floors[1]) ||
                          ((floor > 3'd3) && calls[2] && unlocked_floors[2]) ||
                          ((floor > 3'd4) && calls[3] && unlocked_floors[3]);

    // Divisor de clock para movimento automático
    reg [25:0] counter = 0;
    
    // Gera um pulso a cada ~1 segundo (50MHz / 50M = 1Hz)
    wire move_tick = (counter == 26'd50000000);
    
    always @(posedge CLOCK_50) begin
        if (counter == 26'd50000000) begin
            counter <= 0;
        end else begin
            counter <= counter + 1'b1;
        end
    end
    
    // Lógica do elevador: move automaticamente
    reg [2:0] next_floor;
    
    always @(posedge CLOCK_50) begin
        // Atualiza quais andares estão desbloqueados baseado nos switches SW[7:5]
        // SW[7:5] = 000 (0): todos desbloqueados
        // SW[7:5] = 001 (1): bloqueia andar 1
        // SW[7:5] = 010 (2): bloqueia andar 2
        // SW[7:5] = 011 (3): bloqueia andar 3
        // SW[7:5] = 100 (4): bloqueia andar 4
        // SW[7:5] = 101 (5): bloqueia andar 5
        // SW[7:5] = 110-111 (6-7): todos desbloqueados (valores inválidos, limitado a 5)
        if (blocked_floor_sw >= 3'd1 && blocked_floor_sw <= 3'd5) begin
            // Bloqueia o andar especificado, desbloqueia os demais
            case (blocked_floor_sw)
                3'd1: begin
                    unlocked_floors <= 5'b11110;  // Bloqueia andar 1
                    calls[0] <= 1'b0;  // Limpa chamada do andar bloqueado
                end
                3'd2: begin
                    unlocked_floors <= 5'b11101;  // Bloqueia andar 2
                    calls[1] <= 1'b0;  // Limpa chamada do andar bloqueado
                end
                3'd3: begin
                    unlocked_floors <= 5'b11011;  // Bloqueia andar 3
                    calls[2] <= 1'b0;  // Limpa chamada do andar bloqueado
                end
                3'd4: begin
                    unlocked_floors <= 5'b10111;  // Bloqueia andar 4
                    calls[3] <= 1'b0;  // Limpa chamada do andar bloqueado
                end
                3'd5: begin
                    unlocked_floors <= 5'b01111;  // Bloqueia andar 5
                    calls[4] <= 1'b0;  // Limpa chamada do andar bloqueado
                end
                default: unlocked_floors <= 5'b11111;  // Todos desbloqueados
            endcase
        end else begin
            // Se o valor for 0, 6 ou 7, todos os andares ficam desbloqueados
            unlocked_floors <= 5'b11111;
        end
        
        // Ativa modo emergência quando KEY[0] for pressionado
        if (emergency_pressed) begin
            emergency_mode <= 1'b1;
            calls <= 5'b0;  // Descarta todas as requisições
        end
        // Controle de pessoas (não funciona em modo emergência)
        else if (!emergency_mode) begin
            if (add_person && people < 2'd3) people <= people + 1;
            if (rem_person && people > 2'd0) people <= people - 1;
        end
        
        // Modo emergência ativo: mantém chamadas zeradas
        if (emergency_mode) begin
            calls <= 5'b0;  // Força calls zeradas durante TODA a emergência
        end
        // Modo standby: move para o último andar (5)
        else if (standby_mode && move_tick) begin
            if (floor < 3'd5) begin
                floor <= floor + 1'b1;  // Sobe para o último andar
                state <= UP;
            end else begin
                // Já está no último andar
                state <= IDLE;
            end
        end
        // Move automaticamente quando move_tick ocorrer (apenas se não estiver em standby)
        else if (move_tick && !standby_mode) begin
            // Modo normal: atende chamadas (move um andar por vez)
            if (!is_full && calls != 5'b0) begin
                // Decide movimento: sempre um andar por vez
                if (has_call_above && (state == UP || state == IDLE || !has_call_below)) begin
                    // Sobe um andar
                    floor <= floor + 1'b1;
                    state <= UP;
                end else if (has_call_below) begin
                    // Desce um andar
                    floor <= floor - 1'b1;
                    state <= DOWN;
                end else begin
                    state <= IDLE;
                end
                
                // Limpa chamada do andar atual (se houver)
                case (floor)
                    3'd1: if (calls[0] && unlocked_floors[0]) calls[0] <= 1'b0;
                    3'd2: if (calls[1] && unlocked_floors[1]) calls[1] <= 1'b0;
                    3'd3: if (calls[2] && unlocked_floors[2]) calls[2] <= 1'b0;
                    3'd4: if (calls[3] && unlocked_floors[3]) calls[3] <= 1'b0;
                    3'd5: if (calls[4] && unlocked_floors[4]) calls[4] <= 1'b0;
                endcase
            end else begin
                state <= IDLE;
            end
        end
        // Registra novas chamadas continuamente (apenas em modo normal, sem move_tick, sem standby)
        // Valida se o andar está desbloqueado antes de aceitar a solicitação
        else if (!standby_mode) begin
            calls <= calls | (sw_calls & unlocked_floors);
        end
        
        // Lógica de movimento durante emergência
        if (move_tick && emergency_mode) begin
            if (floor > 3'd1) begin
                floor <= floor - 1'b1;  // Desce um andar
                state <= DOWN;
            end else begin
                // Chegou no térreo, desativa emergência
                emergency_mode <= 1'b0;
                state <= IDLE;
            end
        end
    end
    
    // Display de 7 segmentos para o andar (HEX0)
    reg [6:0] seg_floor;
    always @(*) begin
        if (standby_mode) begin
            seg_floor = 7'b0001000;  // Apenas parte de baixo (segmento d)
        end else if (emergency_mode) begin
            seg_floor = 7'b0111111;  // 0 (para "190")
        end else begin
            case (floor)
                3'd1: seg_floor = 7'b0000110;  // 1
                3'd2: seg_floor = 7'b1011011;  // 2
                3'd3: seg_floor = 7'b1001111;  // 3
                3'd4: seg_floor = 7'b1100110;  // 4
                3'd5: seg_floor = 7'b1101101;  // 5
                default: seg_floor = 7'b0000000;
            endcase
        end
    end

    reg [6:0] seg_direction;
    always @(*) begin
        if (standby_mode) begin
            seg_direction = 7'b0001000;  // Apenas parte de baixo (segmento d)
        end else if (emergency_mode) begin
            seg_direction = 7'b1101111;  // 9 (para "190")
        end else begin
            case (state)
                UP:      seg_direction = 7'b1101101;  // 5 (Subindo)
                DOWN:    seg_direction = 7'b1011110;  // d (Descendo)
                IDLE:    seg_direction = 7'b1110011;  // P (Parado)
                default: seg_direction = 7'b0000000;
            endcase
        end
    end
    
    // Display de 7 segmentos para o número de pessoas (HEX2)
    reg [6:0] seg_people;
    always @(*) begin
        if (standby_mode) begin
            seg_people = 7'b0001000;  // Apenas parte de baixo (segmento d)
        end else if (emergency_mode) begin
            seg_people = 7'b0000110;  // 1 (para "190")
        end else begin
            case (people)
                2'd0: seg_people = 7'b0111111;  // 0
                2'd1: seg_people = 7'b0000110;  // 1
                2'd2: seg_people = 7'b1011011;  // 2
                2'd3: seg_people = 7'b1001111;  // 3
                default: seg_people = 7'b0000000;
            endcase
        end
    end
    
    // Display HEX3 em modo standby
    reg [6:0] seg_hex3;
    always @(*) begin
        if (standby_mode) begin
            seg_hex3 = 7'b0001000;  // Apenas parte de baixo (segmento d)
        end else begin
            seg_hex3 = 7'b1111111;  // Sempre apagado (todos segmentos off)
        end
    end
    
    assign HEX0 = ~seg_floor;      // Andar atual (1-5) ou "0" (para "190") ou parte de baixo (standby)
    assign HEX1 = ~seg_direction;  // Direção (S/D/P) ou "9" (para "190") ou parte de baixo (standby)
    assign HEX2 = ~seg_people;     // Número de pessoas (0-3) ou "1" (para "190") ou parte de baixo (standby)
    assign HEX3 = ~seg_hex3;      // Sempre apagado ou parte de baixo (standby)
    assign LEDR[4:0] = calls;      // Chamadas dos andares
    assign LEDR[9:8] = people;     // Número de pessoas (também nos LEDs)
    assign LEDR[7:5] = blocked_floor_sw;  // LEDs acendem conforme SW[7:5] (andar bloqueado em binário)
    assign LEDG[0] = (state == UP);       // LED verde 0: subindo
    assign LEDG[1] = (state == DOWN);     // LED verde 1: descendo
    assign LEDG[2] = is_full;             // LED verde 2: cheio (3 pessoas)
    assign LEDG[3] = emergency_mode;      // LED verde 3: modo emergência
    assign LEDG[7:4] = 4'b0;

endmodule