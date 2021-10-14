---------------------------------------------------------------------------------------------------------------
-- moving_average_filter
-- 
-- Risorse in implementazione: 95 LUTS 77 FF
-- f_max: 293 MHz
-- 
-- Sono stati implementati appositamente 2 adders e 2 subtractors, elaborando separatamente i dati 'left'
-- e i dati 'right'. L'alternativa era di usare 1 adder, 1 subtractor e 1 mux in serie. Abbiamo scelto la prima per
-- migliorare f_max. Siccome in ingresso non arrivano mai due dati consecutivi con lo stesso 'tlast', la 
-- prima configurazione può essere portata a frequenze maggiori grazie all'interleaving.
-- 
-- La memoria dei dati entranti invece è unica, ovvero i dati left e right non vengono immagazzinati in due
-- shift registers separati, ma in uno solo. Ciò è stato fatto per:
-- 1) avere facilmente a disposizione l'ultimo dato entrato in mem(0), che sia left o right (più avanti verrà
--    spiegato perché è necessaria questa cosa)
-- 2) aumentare le possibilità di un'ottimizzazione migliore da parte di Vivado. Un unico shift register grande ha 
--    più possibilità di essere inferito nella migliore maniera possibile piuttosto che due shift registers separati 
--    con diverse logiche di controllo.
-- 
-- Il filtro continua a lavorare anche quando è OFF, questa scelta è obbligatoria se si vogliono rimuovere 
-- le inevitabili distorsioni audio che si genererebbero ogni volta che enable_filter passa da 0 a 1,
-- dovute ai valori errati immagazzinati nello shift register negli istanti iniziali.
---------------------------------------------------------------------------------------------------------------

---------- DEFAULT LIBRARY ---------
library IEEE;
    use IEEE.STD_LOGIC_1164.ALL;
    use IEEE.NUMERIC_STD.ALL;
------------------------------------

entity moving_avg_filter is
    Generic (
       -- Larghezza di tdata
       DATA_WIDTH : INTEGER := 16;
       
       -- ORDER è il numero di dati su cui fa la media:
       -- numero potenza di 2 : funziona bene
       -- altro numero pari   : funziona, ma richiede più hardware e peggiora f_max
       -- numero dispari      : non funziona
       ORDER : INTEGER := 32 
    );
    Port ( 
       clk : in STD_LOGIC;
       rst : in STD_LOGIC;
       enable_filter : in STD_LOGIC;
       
       s_tdata  : in  STD_LOGIC_VECTOR ( DATA_WIDTH-1 DOWNTO 0 );
       s_tvalid : in  STD_LOGIC;
       s_tlast  : in  STD_LOGIC;
       s_tready : out STD_LOGIC;
       
       m_tdata  : out STD_LOGIC_VECTOR ( DATA_WIDTH-1 DOWNTO 0 );
       m_tvalid : out STD_LOGIC;
       m_tlast  : out STD_LOGIC;
       m_tready : in  STD_LOGIC
       );
end moving_avg_filter ;

architecture Behavioral of moving_avg_filter  is

    -------------------------- CONSTANTS ----------------------------
    constant SHIFT_REG_DEPTH : INTEGER := 2*ORDER;
    -----------------------------------------------------------------
    
    ---------------------------- TYPES ------------------------------
    type matrix is array ( 0 TO SHIFT_REG_DEPTH-1 ) of STD_LOGIC_VECTOR (DATA_WIDTH-1 downto 0);
    -----------------------------------------------------------------
    
    ---------------------------- SIGNALS ----------------------------
    signal mem : matrix;
    signal sum_left, sum_right: INTEGER RANGE -(2**(DATA_WIDTH-1))*ORDER TO (2**(DATA_WIDTH-1)-1)*ORDER;
    signal left_enable, right_enable : STD_LOGIC;
    signal enable_filter_sampled     : STD_LOGIC;
    signal m_tvalid_int, s_tready_int, m_tlast_int : STD_LOGIC;
    signal sel : STD_LOGIC_VECTOR (1 DOWNTO 0);
    -----------------------------------------------------------------

begin     

    --------------------------- DATA FLOW ---------------------------
    s_tready     <= s_tready_int; 
    s_tready_int <= '0' when (m_tvalid_int = '1' and m_tready = '0') or rst = '1' else
                    '1';
    
    m_tvalid <= m_tvalid_int;
    
    m_tlast <= m_tlast_int;
    
    -- Mux per selezionare m_tdata
    sel <= m_tlast_int & enable_filter_sampled;
    with sel select
        m_tdata <= STD_LOGIC_VECTOR ( TO_SIGNED (sum_left  / ORDER, m_tdata'LENGTH)) when "01",
                   STD_LOGIC_VECTOR ( TO_SIGNED (sum_right / ORDER, m_tdata'LENGTH)) when "11",
                   mem(0)                                                            when others; 
    
    -- Siccome ORDER è costante e potenza di 2, 'sum_left / ORDER' è inferito nella maniera corretta, ovvero
    -- ignorando i bit meno significativi, anche con sum_left di tipo signed.
    
    -- Perché scrivere mem(0) e non direttamente s_tdata? 
    -- Per non perdere alcun dato quando cambia 'enable_filter' è necessario ritardare l'uscita di 1 clock cycle, 
    -- sia con filtro ON che con filtro OFF. mem(0) contiene l'ultimo dato che è entrato.          
    
    
    -- right enable e left_enable sono stati introdotti solo per aumentare la leggibilità
    right_enable <= s_tlast;
    left_enable  <= not s_tlast;
    -----------------------------------------------------------------      
    
    --------------------------- PROCESS ----------------------------- 
    process ( clk, rst )
    begin
        ----- ASYNC -----
        if  rst = '1' then
            sum_right <=  0;
            sum_left  <=  0;
            m_tvalid_int <= '0';
            m_tlast_int  <= '0';
            enable_filter_sampled <= '0';  
            
            -- Abbiamo scelto di resettare enable_filter_sampled a '0' invece che a 'enable_filter', perchè:
            -- resettandolo al valore di un input si crea un circuito più complesso, inutile considerando che
            -- i primissimi #ORDER dati sono 'corrotti' perché vengono mischiati con i valori arbitrari  
            -- (per esempio '0') inizialmente immagazzinati nella memoria mem.
            
            -- Qui la riga: mem <= ( OTHERS => ( OTHERS => '0' )) è stata volutamente rimossa perché impediva 
            -- l'infer dei 'Srlc32e', fatti apposta per gli shift registers molto estesi
        
        ----- SYNC -----
        elsif rising_edge (clk) then
            
            if m_tvalid_int = '1' and m_tready = '1' then 
                m_tvalid_int <= '0';   -- eventualmente verrà sovrascritto
                enable_filter_sampled <= enable_filter;  
                -- E' necessario il sampling di 'enable_filter' perché l'input è asincrono, inoltre il sampling
                -- si trova sotto questo if per evitare di infrangere la regola Axis di cambiare tdata nel caso 
                -- in cui il dato precendente non sia ancora stato trasferito
            end if;
            
            
            if s_tvalid = '1' and s_tready_int = '1' then 
            -- (Posso entrarci anche con filtro OFF)
                
                m_tlast_int  <= s_tlast;
                m_tvalid_int <= '1';
                
                if left_enable = '1' then    
                    -- Il dato in ingresso è L
                    sum_left  <= sum_left  + TO_INTEGER ( SIGNED ( s_tdata ) ) - TO_INTEGER ( SIGNED ( mem(SHIFT_REG_DEPTH-1)) );
                end if;
                
                if right_enable = '1' then 
                    -- Il dato in ingresso è R
                    sum_right  <= sum_right  + TO_INTEGER ( SIGNED ( s_tdata ) ) - TO_INTEGER ( SIGNED ( mem(SHIFT_REG_DEPTH-1)) );
                end if;
                
                -- 'if right_enable = '1' avrei potuto scriverlo come 'else' del precedente if, ma in questa maniera esplicito 
                -- l'intenzione di usare il CE pin dei FF
                
                
                mem  <= s_tdata & mem( 0 to SHIFT_REG_DEPTH-2 );
                
            end if;
             
        end if;
    end process;
    -----------------------------------------------------------------
    
end Behavioral;