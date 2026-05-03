-- ============================================================
-- Projeto Integrador 2A -- Engenharia de ComputaÃ§Ã£o -- IESB
-- TÃ­tulo  : Vending Machine -- Top-Level (FSM + Datapath)
-- Arquivo : vending_machine_top.vhd
-- Equipe  : Alisson Antunes, BÃ¡rbara dos Anjos, Gabriela Albino
-- Data    : 2026
-- ============================================================
-- DescriÃ§Ã£o:
--   MÃ³dulo top-level que integra a FSM (unidade de controle) e
--   o Datapath (unidade de processamento). Todos os sinais de
--   controle e status trafegam internamente entre os dois mÃ³dulos.
--   As entradas fÃ­sicas chegam jÃ¡ com debounce aplicado.
--
-- Nota de temporizaÃ§Ã£o:
--   A FSM utiliza estados de espera internos (S3W, S4W) para
--   absorver a latÃªncia de 1 ciclo dos registradores do datapath.
--   Nenhuma lÃ³gica extra Ã© necessÃ¡ria neste nÃ­vel.
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity vending_machine_top is
    generic (
        DATA_WIDTH   : integer := 8;
        NUM_PRODUTOS : integer := 4;
        SEL_WIDTH    : integer := 2
    );
    port (
        -- Interface com a FPGA
        clk             : in  std_logic;
        rst             : in  std_logic;

        -- Entradas fÃ­sicas (apÃ³s debounce)
        moeda_in        : in  std_logic;
        moeda_val       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        sel_produto     : in  std_logic_vector(SEL_WIDTH-1  downto 0);
        sel_pulse       : in  std_logic;
        confirmar       : in  std_logic;
        cancelar        : in  std_logic;

        -- SaÃ­das para atuadores
        libera_produto  : out std_logic;
        libera_troco    : out std_logic;

        -- SaÃ­das para display
        display_mode    : out std_logic_vector(2 downto 0);
        credito_display : out std_logic_vector(DATA_WIDTH-1 downto 0);
        preco_display   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        troco_display   : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity vending_machine_top;

architecture structural of vending_machine_top is

    -- ----------------------------------------------------------
    -- DeclaraÃ§Ã£o dos componentes
    -- ----------------------------------------------------------
    component vending_machine_fsm is
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            moeda_in        : in  std_logic;
            sel_produto     : in  std_logic;
            confirmar       : in  std_logic;
            cancelar        : in  std_logic;
            cmp_result      : in  std_logic;
            troco_positivo  : in  std_logic;
            troco_pronto    : in  std_logic;
            acc_en          : out std_logic;
            cmp_en          : out std_logic;
            sub_en          : out std_logic;
            sel_en          : out std_logic;
            rst_credito     : out std_logic;
            libera_produto  : out std_logic;
            libera_troco    : out std_logic;
            display_mode    : out std_logic_vector(2 downto 0)
        );
    end component;

    component vending_machine_datapath is
        generic (
            DATA_WIDTH   : integer;
            NUM_PRODUTOS : integer;
            SEL_WIDTH    : integer
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            acc_en          : in  std_logic;
            sel_en          : in  std_logic;
            cmp_en          : in  std_logic;
            sub_en          : in  std_logic;
            rst_credito     : in  std_logic;
            moeda_val       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            sel_produto     : in  std_logic_vector(SEL_WIDTH-1  downto 0);
            cmp_result      : out std_logic;
            troco_positivo  : out std_logic;
            troco_pronto    : out std_logic;
            credito_out     : out std_logic_vector(DATA_WIDTH-1 downto 0);
            preco_out       : out std_logic_vector(DATA_WIDTH-1 downto 0);
            troco_out       : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

    -- ----------------------------------------------------------
    -- Sinais internos de interligaÃ§Ã£o FSM â†” Datapath
    -- ----------------------------------------------------------
    signal s_acc_en         : std_logic;
    signal s_cmp_en         : std_logic;
    signal s_sub_en         : std_logic;
    signal s_sel_en         : std_logic;
    signal s_rst_credito    : std_logic;
    signal s_cmp_result     : std_logic;
    signal s_troco_positivo : std_logic;
    signal s_troco_pronto   : std_logic;

    -- Converte vetor de seleÃ§Ã£o em booleano para a FSM:
    -- qualquer valor nÃ£o-zero indica que um produto foi selecionado.
    signal s_sel_produto_bool : std_logic;

begin

    s_sel_produto_bool <= sel_pulse;

    -- ----------------------------------------------------------
    -- InstÃ¢ncia 1: FSM (unidade de controle)
    -- ----------------------------------------------------------
    u_fsm : vending_machine_fsm
        port map (
            clk            => clk,
            rst            => rst,
            moeda_in       => moeda_in,
            sel_produto    => s_sel_produto_bool,
            confirmar      => confirmar,
            cancelar       => cancelar,
            cmp_result     => s_cmp_result,
            troco_positivo => s_troco_positivo,
            troco_pronto   => s_troco_pronto,
            acc_en         => s_acc_en,
            cmp_en         => s_cmp_en,
            sub_en         => s_sub_en,
            sel_en         => s_sel_en,
            rst_credito    => s_rst_credito,
            libera_produto => libera_produto,
            libera_troco   => libera_troco,
            display_mode   => display_mode
        );

    -- ----------------------------------------------------------
    -- InstÃ¢ncia 2: Datapath (unidade de processamento)
    -- ----------------------------------------------------------
    u_datapath : vending_machine_datapath
        generic map (
            DATA_WIDTH   => DATA_WIDTH,
            NUM_PRODUTOS => NUM_PRODUTOS,
            SEL_WIDTH    => SEL_WIDTH
        )
        port map (
            clk            => clk,
            rst            => rst,
            acc_en         => s_acc_en,
            sel_en         => s_sel_en,
            cmp_en         => s_cmp_en,
            sub_en         => s_sub_en,
            rst_credito    => s_rst_credito,
            moeda_val      => moeda_val,
            sel_produto    => sel_produto,
            cmp_result     => s_cmp_result,
            troco_positivo => s_troco_positivo,
            troco_pronto   => s_troco_pronto,
            credito_out    => credito_display,
            preco_out      => preco_display,
            troco_out      => troco_display
        );

end architecture structural;
