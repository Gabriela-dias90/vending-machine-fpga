-- ============================================================
-- Projeto Integrador 2A -- Testbench de IntegraÃ§Ã£o (v3 - Corrigido com Pulso)
-- Arquivo : tb_vending_machine_top.vhd
-- DescriÃ§Ã£o: Valida o sistema completo (FSM + Datapath).
--            Simula transaÃ§Ãµes reais com valores em centavos.
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_vending_machine_top is
end entity tb_vending_machine_top;

architecture sim of tb_vending_machine_top is

    constant CLK_PERIOD  : time    := 10 ns;
    constant DATA_WIDTH  : integer := 8;
    constant SEL_WIDTH   : integer := 2;
    constant TIMEOUT     : time    := 20 * CLK_PERIOD;

    -- DUT
    component vending_machine_top is
        generic (
            DATA_WIDTH   : integer;
            NUM_PRODUTOS : integer;
            SEL_WIDTH    : integer
        );
        port (
            clk             : in  std_logic;
            rst             : in  std_logic;
            moeda_in        : in  std_logic;
            moeda_val       : in  std_logic_vector(DATA_WIDTH-1 downto 0);
            sel_produto     : in  std_logic_vector(SEL_WIDTH-1  downto 0);
            sel_pulse       : in  std_logic;
            confirmar       : in  std_logic;
            cancelar        : in  std_logic;
            libera_produto  : out std_logic;
            libera_troco    : out std_logic;
            display_mode    : out std_logic_vector(2 downto 0);
            credito_display : out std_logic_vector(DATA_WIDTH-1 downto 0);
            preco_display   : out std_logic_vector(DATA_WIDTH-1 downto 0);
            troco_display   : out std_logic_vector(DATA_WIDTH-1 downto 0)
        );
    end component;

    -- EstÃ­mulos
    signal clk             : std_logic := '0';
    signal rst             : std_logic := '0';
    signal moeda_in        : std_logic := '0';
    signal moeda_val       : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    signal sel_produto     : std_logic_vector(SEL_WIDTH-1  downto 0) := (others => '0');
    signal sel_pulse       : std_logic := '0';
    signal confirmar       : std_logic := '0';
    signal cancelar        : std_logic := '0';

    -- ObservaÃ§Ãµes
    signal libera_produto  : std_logic;
    signal libera_troco    : std_logic;
    signal display_mode    : std_logic_vector(2 downto 0);
    signal credito_display : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal preco_display   : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal troco_display   : std_logic_vector(DATA_WIDTH-1 downto 0);

    -- Contador global de falhas
    shared variable num_falhas : integer := 0;

    -- ----------------------------------------------------------
    -- Procedimento: verifica condiÃ§Ã£o e conta falhas
    -- ----------------------------------------------------------
    procedure checar(
        cond : in boolean;
        msg  : in string
    ) is
    begin
        if not cond then
            num_falhas := num_falhas + 1;
            report msg severity error;
        end if;
    end procedure;

    -- ----------------------------------------------------------
    -- Procedimento: reset completo sincronizado
    -- ----------------------------------------------------------
    procedure aplicar_reset(
        signal rst_s : out std_logic
    ) is
    begin
        rst_s <= '1';
        wait for 3 * CLK_PERIOD;
        wait until rising_edge(clk);
        rst_s <= '0';
        wait until rising_edge(clk);
    end procedure;

    -- ----------------------------------------------------------
    -- Procedimento: insere moeda sincronizado com borda de subida.
    -- ----------------------------------------------------------
    procedure inserir_moeda(
        valor       : in  integer;
        signal m_in : out std_logic;
        signal m_val: out std_logic_vector(DATA_WIDTH-1 downto 0)
    ) is
    begin
        wait until falling_edge(clk);
        m_val <= std_logic_vector(to_unsigned(valor, DATA_WIDTH));
        wait until rising_edge(clk);  
        m_in  <= '1';
        wait until rising_edge(clk);
        m_in  <= '0';
        wait until rising_edge(clk);
    end procedure;

    -- ----------------------------------------------------------
    -- Procedimento: seleciona produto e confirma.
    -- ATUALIZADO: Agora gera o gatilho na porta sel_pulse.
    -- ----------------------------------------------------------
    procedure selecionar(
        idx         : in  integer;
        signal sel  : out std_logic_vector(SEL_WIDTH-1 downto 0);
        signal s_pul: out std_logic;
        signal conf : out std_logic
    ) is
    begin
        -- Passo 1: estabelece Ã­ndice (dados)
        wait until falling_edge(clk);
        sel  <= std_logic_vector(to_unsigned(idx, SEL_WIDTH));
        
        -- Passo 2: emite pulso (trigger)
        wait until rising_edge(clk);
        s_pul <= '1'; 
        wait until rising_edge(clk);
        s_pul <= '0';
        
        wait until rising_edge(clk); -- FSM transita S1â†’S2; sel_en ativo
        wait until rising_edge(clk); -- ROM carrega preÃ§o
        
        -- Passo 3: confirma
        conf <= '1';
        wait until rising_edge(clk);
        conf <= '0';
        wait until rising_edge(clk);  
    end procedure;

    -- ----------------------------------------------------------
    -- Procedimento: aguarda sinal atingir valor desejado
    -- ----------------------------------------------------------
    procedure aguardar_sinal(
        signal s     : in  std_logic;
        val          : in  std_logic;
        msg_timeout  : in  string
    ) is
        variable t_inicio : time;
    begin
        t_inicio := now;
        while s /= val loop
            wait until rising_edge(clk);
            if (now - t_inicio) >= TIMEOUT then
                report "TIMEOUT: " & msg_timeout severity error;
                num_falhas := num_falhas + 1;
                exit;
            end if;
        end loop;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : vending_machine_top
        generic map (DATA_WIDTH => DATA_WIDTH, NUM_PRODUTOS => 4, SEL_WIDTH => SEL_WIDTH)
        port map (
            clk             => clk,
            rst             => rst,
            moeda_in        => moeda_in,
            moeda_val       => moeda_val,
            sel_produto     => sel_produto,
            sel_pulse       => sel_pulse,
            confirmar       => confirmar,
            cancelar        => cancelar,
            libera_produto  => libera_produto,
            libera_troco    => libera_troco,
            display_mode    => display_mode,
            credito_display => credito_display,
            preco_display   => preco_display,
            troco_display   => troco_display
        );

    proc_stim : process
    begin
        aplicar_reset(rst);

        -- ======================================================
        -- TC01: Compra exata - Produto 0
        -- ======================================================
        report "TC01: Compra exata - Produto 0 (100 centavos)";
        inserir_moeda(100, moeda_in, moeda_val);
        selecionar(0, sel_produto, sel_pulse, confirmar); -- ATUALIZADO

        aguardar_sinal(libera_produto, '1', "TC01 - libera_produto nao ativado");
        checar(libera_produto = '1', "TC01 FALHOU: produto nao liberado");
        checar(to_integer(unsigned(troco_display)) = 0, "TC01 FALHOU: troco esperado 0");
        checar(libera_troco = '0', "TC01 FALHOU: libera_troco nao deveria estar ativo");
        report "TC01: OK";

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        aplicar_reset(rst);

        -- ======================================================
        -- TC02: Compra com troco - Produto 0
        -- ======================================================
        report "TC02: Compra com troco - inserir 150, produto custa 100";
        inserir_moeda(100, moeda_in, moeda_val);
        inserir_moeda(50,  moeda_in, moeda_val);
        selecionar(0, sel_produto, sel_pulse, confirmar); -- ATUALIZADO
        
        aguardar_sinal(libera_produto, '1', "TC02 - libera_produto nao ativado");
        checar(libera_produto = '1', "TC02 FALHOU: produto nao liberado");
        
        aguardar_sinal(libera_troco, '1', "TC02 - libera_troco nao ativado");
        checar(libera_troco = '1', "TC02 FALHOU: troco nao liberado");
        checar(to_integer(unsigned(troco_display)) = 50, "TC02 FALHOU: troco esperado 50");
        report "TC02: OK";

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        aplicar_reset(rst);

        -- ======================================================
        -- TC03: CrÃ©dito insuficiente â†’ completar e reconfirmar
        -- ======================================================
        report "TC03: Credito insuficiente - inserir 50 (custa 100)";
        inserir_moeda(50, moeda_in, moeda_val);
        selecionar(0, sel_produto, sel_pulse, confirmar); -- ATUALIZADO

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        checar(libera_produto = '0', "TC03 FALHOU: produto nao deveria ser liberado");
        
        inserir_moeda(50, moeda_in, moeda_val);
        selecionar(0, sel_produto, sel_pulse, confirmar); -- ATUALIZADO
        
        aguardar_sinal(libera_produto, '1', "TC03 - produto nao liberado apos completar credito");
        checar(libera_produto = '1', "TC03 FALHOU: produto deveria ser liberado");
        report "TC03: OK";

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        aplicar_reset(rst);

        -- ======================================================
        -- TC04: Produto mais caro - Produto 2
        -- ======================================================
        report "TC04: Produto 2 (200 centavos), inserir 3x75 = 225";
        inserir_moeda(75, moeda_in, moeda_val);
        inserir_moeda(75, moeda_in, moeda_val);
        inserir_moeda(75, moeda_in, moeda_val);

        wait until rising_edge(clk);
        checar(to_integer(unsigned(credito_display)) = 225, "TC04 FALHOU: credito_display esperado 225");
        
        selecionar(2, sel_produto, sel_pulse, confirmar); -- ATUALIZADO

        aguardar_sinal(libera_produto, '1', "TC04 - produto nao liberado");
        checar(libera_produto = '1', "TC04 FALHOU: produto nao liberado");
        
        aguardar_sinal(libera_troco, '1', "TC04 - troco nao liberado");
        checar(to_integer(unsigned(troco_display)) = 25, "TC04 FALHOU: troco esperado 25");
        report "TC04: OK";

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        aplicar_reset(rst);

        -- ======================================================
        -- TC05: Cancelamento durante inserÃ§Ã£o de moedas
        -- ======================================================
        report "TC05: Cancelamento durante insercao de moedas";
        inserir_moeda(50, moeda_in, moeda_val);

        wait until rising_edge(clk);
        cancelar <= '1';
        wait until rising_edge(clk);
        cancelar <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        
        checar(libera_produto = '0', "TC05 FALHOU: produto nao deveria ser liberado apos cancelar");
        checar(display_mode = "000", "TC05 FALHOU: sistema deveria retornar a IDLE apos cancelar");
        report "TC05: OK";

        -- ======================================================
        -- TC06: Overflow de crÃ©dito (inserÃ§Ã£o excessiva)
        -- ======================================================
        report "TC06: Verificacao de overflow de credito";
        inserir_moeda(200, moeda_in, moeda_val);
        inserir_moeda(100, moeda_in, moeda_val);

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        checar(display_mode /= "ZZZ", "TC06 FALHOU: display_mode invalido apos insercao excessiva");
        report "TC06: OK (verificar comportamento de overflow no waveform)";

        aplicar_reset(rst);

        -- ======================================================
        -- TC07: Reset assÃ­ncrono no meio de uma transaÃ§Ã£o
        -- ======================================================
        report "TC07: Reset assÃ­ncrono durante transacao";
        inserir_moeda(75, moeda_in, moeda_val);
        inserir_moeda(75, moeda_in, moeda_val);

        wait for CLK_PERIOD / 4;
        rst <= '1';
        wait for CLK_PERIOD;
        checar(display_mode = "000", "TC07 FALHOU: reset assÃ­ncrono deve forcar IDLE imediatamente");
        
        rst <= '0';
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        checar(libera_produto = '0', "TC07 FALHOU: libera_produto deve ser 0 apos reset");
        checar(libera_troco = '0', "TC07 FALHOU: libera_troco deve ser 0 apos reset");
        report "TC07: OK";

        -- ======================================================
        -- Resumo final
        -- ======================================================
        report "============================================";
        report "Simulacao de integracao concluida.";
        if num_falhas = 0 then
            report "RESULTADO: PASSOU - Nenhuma falha detectada." severity note;
        else
            report "RESULTADO: FALHOU - " & integer'image(num_falhas) & " falha(s) detectada(s)." severity failure;
        end if;
        report "============================================";
        wait;
    end process proc_stim;

end architecture sim;
