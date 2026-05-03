-- ============================================================
-- Projeto Integrador 2A -- Engenharia de ComputaÃ§Ã£o -- IESB
-- TÃ­tulo  : Vending Machine -- Unidade de Controle (FSM)
-- Arquivo : vending_machine_fsm.vhd
-- Equipe  : Alisson Antunes, BÃ¡rbara dos Anjos, Gabriela Albino
-- Data    : 2026
-- Ferram. : Vivado 2017.2 / ModelSim
-- Placa   : Xilinx Nexys A7 100T
-- ============================================================
-- DescriÃ§Ã£o:
--   MÃ¡quina de Estados Finita (FSM) estilo Moore para controle
--   completo da Vending Machine. Separada do datapath conforme
--   boas prÃ¡ticas de sistemas digitais sÃ­ncronos.
--
-- Estados:
--   S0 - IDLE              : aguarda interaÃ§Ã£o do usuÃ¡rio
--   S1 - INSERINDO_MOEDA   : acumula crÃ©dito no datapath
--   S2 - SELECAO_PRODUTO   : seleÃ§Ã£o e carregamento de preÃ§o
--   S3 - VERIF_CREDITO     : ativa cmp_en e aguarda resultado
--   S3W- WAIT_CMP          : aguarda 1 ciclo para resultado estabilizar
--   S4 - LIBERANDO_PRODUTO : ativa sub_en e aciona entrega
--   S4W- WAIT_SUB          : aguarda 1 ciclo para troco estabilizar
--   S5 - DEVOLVENDO_TROCO  : devolve troco e reseta crÃ©dito
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- ENTITY
-- ============================================================
entity vending_machine_fsm is
    port (
        -- Interface global
        clk             : in  std_logic;                      -- Clock da FPGA
        rst             : in  std_logic;                      -- Reset sÃ­ncrono, ativo em '1'

        -- Entradas do usuÃ¡rio (vindas do mÃ³dulo de debounce)
        moeda_in        : in  std_logic;                      -- Pulso: moeda detectada
        sel_produto     : in  std_logic;                      -- Pulso: botÃ£o de seleÃ§Ã£o pressionado
        confirmar       : in  std_logic;                      -- Pulso: confirmar compra
        cancelar        : in  std_logic;                      -- Pulso: cancelar operaÃ§Ã£o

        -- Sinais de status vindos do datapath
        cmp_result      : in  std_logic;                      -- '1' se crÃ©dito >= preÃ§o
        troco_positivo  : in  std_logic;                      -- '1' se troco > 0
        troco_pronto    : in  std_logic;                      -- '1' quando troco foi liberado

        -- Sinais de controle para o datapath
        acc_en          : out std_logic;                      -- Habilita acumulador de crÃ©dito
        cmp_en          : out std_logic;                      -- Habilita comparador
        sub_en          : out std_logic;                      -- Habilita subtrator (troco)
        sel_en          : out std_logic;                      -- Habilita leitura de preÃ§o (mem. produtos)
        rst_credito     : out std_logic;                      -- Zera registrador de crÃ©dito

        -- SaÃ­das para atuadores e display
        libera_produto  : out std_logic;                      -- Aciona mecanismo de entrega
        libera_troco    : out std_logic;                      -- Aciona devoluÃ§Ã£o de troco
        display_mode    : out std_logic_vector(2 downto 0)    -- CÃ³digo de mensagem para display
        -- "000" = "Insira moedas"
        -- "001" = valor acumulado
        -- "010" = nome e preÃ§o do produto
        -- "011" = "Aguardando verificaÃ§Ã£o..."
        -- "100" = "Produto liberado!"
        -- "101" = "Troco: R$X,XX"
        -- "110" = "CrÃ©dito insuficiente"
    );
end entity vending_machine_fsm;

-- ============================================================
-- ARCHITECTURE
-- ============================================================
architecture rtl of vending_machine_fsm is

    -- ----------------------------------------------------------
    -- DefiniÃ§Ã£o dos estados
    -- ----------------------------------------------------------
        type t_estado is (
            S0_IDLE,
            S1_INSERINDO_MOEDA,     -- Ativa acc_en por apenas 1 ciclo
            S1_ESPERA,              -- NOVO ESTADO: Aguarda aÃ§Ã£o do usuÃ¡rio
            S2_SELECAO_PRODUTO,
            S3_VERIF_CREDITO,
            S3W_WAIT_CMP,
            S4_LIBERANDO_PRODUTO,
            S4W_WAIT_SUB,
            S5_DEVOLVENDO_TROCO
        );

    -- Registradores de estado (atual e prÃ³ximo)
    signal estado_atual   : t_estado := S0_IDLE;
    signal proximo_estado : t_estado;

begin

    -- ==========================================================
    -- PROCESSO 1: Registro de estado (sÃ­ncrono com reset)
    -- ==========================================================
    proc_registro : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                estado_atual <= S0_IDLE;
            else
                estado_atual <= proximo_estado;
            end if;
        end if;
    end process proc_registro;

    -- ==========================================================
    -- PROCESSO 2: LÃ³gica de transiÃ§Ã£o de estado (combinacional)
    -- ==========================================================
    proc_transicao : process(
        estado_atual,
        moeda_in, sel_produto, confirmar, cancelar,
        cmp_result, troco_positivo, troco_pronto
    )
    begin
        -- Valor padrÃ£o: permanece no estado atual
        proximo_estado <= estado_atual;

        case estado_atual is

            -- --------------------------------------------------
            -- S0: IDLE
            -- --------------------------------------------------
            when S0_IDLE =>
                if moeda_in = '1' then
                    proximo_estado <= S1_INSERINDO_MOEDA;
                elsif sel_produto = '1' then
                    proximo_estado <= S2_SELECAO_PRODUTO;
                end if;

            -- --------------------------------------------------
            -- S1: INSERINDO_MOEDA (Soma e sai imediatamente)
            -- --------------------------------------------------
            when S1_INSERINDO_MOEDA =>
                proximo_estado <= S1_ESPERA; 
            
            -- --------------------------------------------------
            -- S1_ESPERA: Aguarda nova moeda ou seleÃ§Ã£o
            -- --------------------------------------------------
            when S1_ESPERA =>
                if cancelar = '1' then
                    proximo_estado <= S0_IDLE;
                elsif sel_produto = '1' then
                    proximo_estado <= S2_SELECAO_PRODUTO;
                elsif moeda_in = '1' then
                    proximo_estado <= S1_INSERINDO_MOEDA;
                end if;            

            -- --------------------------------------------------
            -- S2: SELECAO_PRODUTO
            -- --------------------------------------------------
            when S2_SELECAO_PRODUTO =>
                if cancelar = '1' then
                    proximo_estado <= S0_IDLE;
                elsif confirmar = '1' then
                    proximo_estado <= S3_VERIF_CREDITO;
                elsif moeda_in = '1' then
                    proximo_estado <= S1_INSERINDO_MOEDA;
                end if;

            -- --------------------------------------------------
            -- S3: VERIF_CREDITO
            -- cmp_en Ã© ativado neste estado (saÃ­da Moore).
            -- O resultado sÃ³ estarÃ¡ em cmp_result no ciclo seguinte.
            -- â†’ AvanÃ§a para S3W incondicionalmente.
            -- --------------------------------------------------
            when S3_VERIF_CREDITO =>
                proximo_estado <= S3W_WAIT_CMP;

            -- --------------------------------------------------
            -- S3W: WAIT_CMP (CorreÃ§Ã£o do retorno por falta de crÃ©dito)
            -- --------------------------------------------------
            when S3W_WAIT_CMP =>
                if cmp_result = '1' then
                    proximo_estado <= S4_LIBERANDO_PRODUTO;
                else
                    proximo_estado <= S1_ESPERA; -- CORREÃ‡ÃƒO: Volta para espera
                end if;

            -- --------------------------------------------------
            -- S4: LIBERANDO_PRODUTO
            -- sub_en Ã© ativado neste estado (saÃ­da Moore).
            -- troco_positivo sÃ³ estarÃ¡ vÃ¡lido no ciclo seguinte.
            -- â†’ AvanÃ§a para S4W incondicionalmente.
            -- --------------------------------------------------
            when S4_LIBERANDO_PRODUTO =>
                proximo_estado <= S4W_WAIT_SUB;

            -- --------------------------------------------------
            -- S4W: WAIT_SUB
            -- troco_positivo agora estÃ¡ vÃ¡lido.
            -- --------------------------------------------------
            when S4W_WAIT_SUB =>
                if troco_positivo = '1' then
                    proximo_estado <= S5_DEVOLVENDO_TROCO;
                else
                    proximo_estado <= S0_IDLE;
                end if;

            -- --------------------------------------------------
            -- S5: DEVOLVENDO_TROCO
            -- --------------------------------------------------
            when S5_DEVOLVENDO_TROCO =>
                if troco_pronto = '1' then
                    proximo_estado <= S0_IDLE;
                end if;

            -- --------------------------------------------------
            -- Cobertura de estado invÃ¡lido (RNF08)
            -- --------------------------------------------------
            when others =>
                proximo_estado <= S0_IDLE;

        end case;
    end process proc_transicao;

    -- ==========================================================
    -- PROCESSO 3: LÃ³gica de saÃ­da Moore (combinacional)
    -- As saÃ­das dependem APENAS do estado atual.
    -- ==========================================================
    proc_saida : process(estado_atual)
    begin
        -- Safe defaults: todos inativos
        acc_en         <= '0';
        cmp_en         <= '0';
        sub_en         <= '0';
        sel_en         <= '0';
        rst_credito    <= '0';
        libera_produto <= '0';
        libera_troco   <= '0';
        display_mode   <= "000";

        case estado_atual is

            when S0_IDLE =>
                display_mode <= "000";   -- "Insira moedas"

            when S1_INSERINDO_MOEDA =>
                acc_en       <= '1';   -- soma moeda ao acumulador
                display_mode <= "001"; -- exibe crÃ©dito total

            when S1_ESPERA =>
                -- acc_en fica '0' automaticamente pelo valor padrÃ£o do topo
                display_mode <= "001"; -- mantÃ©m exibindo o crÃ©dito

            when S2_SELECAO_PRODUTO =>
                sel_en       <= '1';     -- carrega preÃ§o da ROM
                display_mode <= "010";   -- exibe produto e preÃ§o

            when S3_VERIF_CREDITO =>
                cmp_en       <= '1';     -- dispara comparaÃ§Ã£o (resultado no prÃ³ximo ciclo)
                display_mode <= "011";   -- "Aguardando verificaÃ§Ã£o..."

            when S3W_WAIT_CMP =>
                display_mode <= "011";   -- mantÃ©m "Aguardando..." enquanto espera

            when S4_LIBERANDO_PRODUTO =>
                libera_produto <= '1';   -- aciona mecanismo fÃ­sico
                sub_en         <= '1';   -- calcula troco (resultado no prÃ³ximo ciclo)
                display_mode   <= "100"; -- "Produto liberado!"

            when S4W_WAIT_SUB =>
                libera_produto <= '1';   -- mantÃ©m produto liberado durante espera
                display_mode   <= "100";

            when S5_DEVOLVENDO_TROCO =>
                libera_troco <= '1';     -- aciona devoluÃ§Ã£o de troco
                rst_credito  <= '1';     -- zera registrador de crÃ©dito
                display_mode <= "101";   -- "Troco: R$X,XX"

            when others =>
                null;

        end case;
    end process proc_saida;

end architecture rtl;


-- ============================================================
-- PACOTE AUXILIAR: constantes de display_mode
-- ============================================================
-- package vending_pkg is
--     constant DISP_INSIRA    : std_logic_vector(2 downto 0) := "000";
--     constant DISP_CREDITO   : std_logic_vector(2 downto 0) := "001";
--     constant DISP_PRODUTO   : std_logic_vector(2 downto 0) := "010";
--     constant DISP_AGUARD    : std_logic_vector(2 downto 0) := "011";
--     constant DISP_LIBERADO  : std_logic_vector(2 downto 0) := "100";
--     constant DISP_TROCO     : std_logic_vector(2 downto 0) := "101";
--     constant DISP_INSUFIC   : std_logic_vector(2 downto 0) := "110";
-- end package vending_pkg;
