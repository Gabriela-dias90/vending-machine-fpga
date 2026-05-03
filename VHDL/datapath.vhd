-- ============================================================
-- Projeto Integrador 2A -- Engenharia de ComputaÃ§Ã£o -- IESB
-- TÃ­tulo  : Vending Machine -- Datapath
-- Arquivo : vending_machine_datapath.vhd
-- Equipe  : Alisson Antunes, BÃ¡rbara dos Anjos, Gabriela Albino
-- Data    : 2026
-- Ferram. : Vivado 2017.2 / ModelSim
-- Placa   : Xilinx Nexys A7 100T
-- ============================================================
-- DescriÃ§Ã£o:
--   Datapath da Vending Machine. ResponsÃ¡vel por todo o
--   processamento aritmÃ©tico do sistema, operando sob controle
--   direto da FSM. Composto por:
--
--   1. Acumulador de crÃ©dito  : registrador + somador
--   2. MemÃ³ria de produtos    : ROM com preÃ§os prÃ©-definidos
--   3. Comparador             : crÃ©dito >= preÃ§o
--   4. Subtrator              : troco = crÃ©dito - preÃ§o
--
-- ParÃ¢metros genÃ©ricos (configurÃ¡veis na instÃ¢ncia):
--   DATA_WIDTH   : largura dos barramentos de valor (padrÃ£o 8 bits â†’ max R$2,55)
--   NUM_PRODUTOS : nÃºmero de produtos disponÃ­veis     (padrÃ£o 4)
--   SEL_WIDTH    : bits para endereÃ§ar os produtos    (padrÃ£o 2)
--
-- ConvenÃ§Ã£o de valores: 1 unidade = R$0,01 (centavos)
--   Ex.: valor 150 representa R$1,50
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ============================================================
-- ENTITY
-- ============================================================
entity vending_machine_datapath is
    generic (
        DATA_WIDTH   : integer := 8;   -- bits de valor (0..255 centavos)
        NUM_PRODUTOS : integer := 4;   -- produtos disponÃ­veis
        SEL_WIDTH    : integer := 2    -- bits para selecionar produto (2^2 = 4)
    );
    port (
        -- Interface global
        clk             : in  std_logic;
        rst             : in  std_logic;   -- reset sÃ­ncrono, ativo em '1'

        -- --------------------------------------------------------
        -- Sinais de controle vindos da FSM
        -- --------------------------------------------------------
        acc_en          : in  std_logic;   -- habilita acumulaÃ§Ã£o de crÃ©dito
        sel_en          : in  std_logic;   -- habilita leitura de preÃ§o
        cmp_en          : in  std_logic;   -- habilita comparaÃ§Ã£o
        sub_en          : in  std_logic;   -- habilita cÃ¡lculo de troco
        rst_credito     : in  std_logic;   -- zera registrador de crÃ©dito

        -- --------------------------------------------------------
        -- Entradas de dados
        -- --------------------------------------------------------
        moeda_val       : in  std_logic_vector(DATA_WIDTH-1 downto 0);  -- valor da moeda inserida
        sel_produto     : in  std_logic_vector(SEL_WIDTH-1  downto 0);  -- Ã­ndice do produto

        -- --------------------------------------------------------
        -- Sinais de status para a FSM
        -- --------------------------------------------------------
        cmp_result      : out std_logic;   -- '1' se crÃ©dito >= preÃ§o (registrado)
        troco_positivo  : out std_logic;   -- '1' se troco > 0 (registrado)
        troco_pronto    : out std_logic;   -- '1' no ciclo apÃ³s sub_en='1'

        -- --------------------------------------------------------
        -- SaÃ­das de valor para display e troco
        -- --------------------------------------------------------
        credito_out     : out std_logic_vector(DATA_WIDTH-1 downto 0);  -- crÃ©dito atual
        preco_out       : out std_logic_vector(DATA_WIDTH-1 downto 0);  -- preÃ§o do produto
        troco_out       : out std_logic_vector(DATA_WIDTH-1 downto 0)   -- valor do troco
    );
end entity vending_machine_datapath;

-- ============================================================
-- ARCHITECTURE
-- ============================================================
architecture rtl of vending_machine_datapath is

    -- ----------------------------------------------------------
    -- Tipos e constantes
    -- ----------------------------------------------------------

    -- Tipo para a ROM de produtos
    type t_rom_produtos is array(0 to NUM_PRODUTOS-1)
        of unsigned(DATA_WIDTH-1 downto 0);

    -- Tabela de preÃ§os (em centavos). Altere conforme o projeto.
    --   Produto 0: R$1,00 â†’ 100
    --   Produto 1: R$1,50 â†’ 150
    --   Produto 2: R$2,00 â†’ 200
    --   Produto 3: R$0,75 â†’  75
    constant ROM_PRECOS : t_rom_produtos := (
        0 => to_unsigned(100, DATA_WIDTH),
        1 => to_unsigned(150, DATA_WIDTH),
        2 => to_unsigned(200, DATA_WIDTH),
        3 => to_unsigned( 75, DATA_WIDTH)
    );

    -- Limite mÃ¡ximo representÃ¡vel: todos os bits em '1'
    constant MAX_VAL : unsigned(DATA_WIDTH-1 downto 0) := (others => '1');

    -- ----------------------------------------------------------
    -- Sinais internos
    -- ----------------------------------------------------------

    -- Registrador de crÃ©dito acumulado
    signal credito_reg    : unsigned(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Valor lido da ROM de produtos
    signal preco_reg      : unsigned(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Resultado do subtrator (troco)
    signal troco_reg      : unsigned(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Resultado da comparaÃ§Ã£o (registrado para estabilidade)
    signal cmp_reg        : std_logic := '0';

    -- Flag de troco calculado (pulso de 1 ciclo â†’ troco_pronto)
    signal troco_calc     : std_logic := '0';

    -- Flag de troco positivo REGISTRADA (evita glitch com rst_credito)
    signal troco_pos_reg  : std_logic := '0';

begin

    -- ==========================================================
    -- BLOCO 1: Acumulador de crÃ©dito
    -- Registrador sÃ­ncrono com enable e reset.
    -- Quando acc_en='1', soma o valor da moeda ao crÃ©dito atual.
    -- Quando rst_credito='1', zera o registrador (fim de transaÃ§Ã£o).
    -- ProteÃ§Ã£o de overflow: satura em MAX_VAL sem usar 2**DATA_WIDTH.
    -- ==========================================================
    proc_acumulador : process(clk)
        variable soma : unsigned(DATA_WIDTH downto 0);  -- 1 bit extra para detectar overflow
    begin
        if rising_edge(clk) then
            if rst = '1' or rst_credito = '1' then
                credito_reg <= (others => '0');
            elsif acc_en = '1' then
                -- Soma com bit extra para detecÃ§Ã£o segura de overflow
                soma := ('0' & credito_reg) + ('0' & unsigned(moeda_val));
                if soma(DATA_WIDTH) = '1' then
                    credito_reg <= MAX_VAL;   -- satura no mÃ¡ximo representÃ¡vel
                else
                    credito_reg <= soma(DATA_WIDTH-1 downto 0);
                end if;
            end if;
        end if;
    end process proc_acumulador;

    -- ==========================================================
    -- BLOCO 2: MemÃ³ria de produtos (ROM)
    -- Leitura sÃ­ncrona: quando sel_en='1', registra o preÃ§o do
    -- produto selecionado no prÃ³ximo ciclo de clock.
    -- ==========================================================
    proc_rom_produtos : process(clk)
        variable idx : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                preco_reg <= (others => '0');
            elsif sel_en = '1' then
                idx := to_integer(unsigned(sel_produto));
                -- ProteÃ§Ã£o contra Ã­ndice invÃ¡lido
                if idx < NUM_PRODUTOS then
                    preco_reg <= ROM_PRECOS(idx);
                else
                    preco_reg <= MAX_VAL;   -- preÃ§o invÃ¡lido = mÃ¡ximo
                end if;
            end if;
        end if;
    end process proc_rom_produtos;

    -- ==========================================================
    -- BLOCO 3: Comparador
    -- Resultado registrado quando cmp_en='1'.
    -- A FSM deve aguardar 1 ciclo apÃ³s ativar cmp_en para ler
    -- cmp_result (estado S3W na FSM).
    -- cmp_result='1'  â†’  crÃ©dito >= preÃ§o  (compra aprovada)
    -- cmp_result='0'  â†’  crÃ©dito <  preÃ§o  (insuficiente)
    -- ==========================================================
    proc_comparador : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cmp_reg <= '0';
            elsif cmp_en = '1' then
                if credito_reg >= preco_reg then
                    cmp_reg <= '1';
                else
                    cmp_reg <= '0';
                end if;
            end if;
        end if;
    end process proc_comparador;

    -- ==========================================================
    -- BLOCO 4: Subtrator de troco
    -- Calcula troco = crÃ©dito - preÃ§o.
    -- Ativado quando sub_en='1' (estado S4 da FSM).
    -- ProteÃ§Ã£o contra underflow: resultado mÃ­nimo Ã© zero.
    -- Gera troco_pronto por 1 ciclo para sinalizar Ã  FSM.
    -- troco_pos_reg registra se o troco Ã© positivo - evita glitch
    -- causado por rst_credito zerando troco_reg prematuramente.
    -- ==========================================================
    proc_subtrator : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or rst_credito = '1' then
                troco_reg     <= (others => '0');
                troco_calc    <= '0';
                troco_pos_reg <= '0';
            elsif sub_en = '1' then
                if credito_reg > preco_reg then
                    troco_reg     <= credito_reg - preco_reg;
                    troco_pos_reg <= '1';   -- troco positivo
                else
                    troco_reg     <= (others => '0');
                    troco_pos_reg <= '0';   -- sem troco
                end if;
                troco_calc <= '1';          -- sinaliza conclusÃ£o em qualquer caso
            else
                troco_calc <= '0';          -- pulso de 1 ciclo
            end if;
        end if;
    end process proc_subtrator;

    -- ==========================================================
    -- ConexÃµes de saÃ­da
    -- ==========================================================
    credito_out    <= std_logic_vector(credito_reg);
    preco_out      <= std_logic_vector(preco_reg);
    troco_out      <= std_logic_vector(troco_reg);
    cmp_result     <= cmp_reg;
    troco_positivo <= troco_pos_reg;   -- sinal registrado (sem glitch)
    troco_pronto   <= troco_calc;

end architecture rtl;
