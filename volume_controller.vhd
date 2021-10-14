---------------------------------------------------------------------------------------------------------------
-- volume_controller
--
-- Per migliorare il critical path dell'intero sistema, il modulo è stato pipelinizzato in due stadi.
-- 
-- VOLUME_MIN indica il minimo raggiungibile, VOLUME_MAX il massimo.
-- VOLUME_DEFAULT è il valore 'neutro' del volume (né amplificazione né attenuazione), nonché valore iniziale
-- E' necessario che VOLUME_MIN <= VOLUME_DEFAULT <= VOLUME_MAX per funzionare correttamente 
-- Questa scelta consente all'utente di avere una libertà totale
-- con la possibilità di andare oltre ad un'amplificazione di 2^8
---------------------------------------------------------------------------------------------------------------

---------- DEFAULT LIBRARY ---------
library IEEE;
	use IEEE.STD_LOGIC_1164.all;
	use IEEE.NUMERIC_STD.ALL;
------------------------------------

entity volume_controller is
    Generic (
        -- Larghezza di tdata
        DATA_WIDTH      : INTEGER := 16;
        -- Volume neutro, valore iniziale
        VOLUME_DEFAULT  : INTEGER := 7;
        -- Massimo volume 
        VOLUME_MAX      : INTEGER := 15;
        -- Minimo volume
        VOLUME_MIN      : INTEGER := 0
        );
    Port ( 
       clk : in     STD_LOGIC;
       rst : in     STD_LOGIC;
       
       volume_up    : in  STD_LOGIC;
       volume_down  : in  STD_LOGIC;
       volume_level : out STD_LOGIC_VECTOR ( VOLUME_MAX - VOLUME_MIN DOWNTO 0 );
       
       s_tdata  : in  STD_LOGIC_VECTOR ( DATA_WIDTH-1 DOWNTO 0 );
       s_tvalid : in  STD_LOGIC;
       s_tlast  : in  STD_LOGIC;
       s_tready : out STD_LOGIC;
       
       m_tdata  : out STD_LOGIC_VECTOR ( DATA_WIDTH-1 DOWNTO 0 );
       m_tvalid : out STD_LOGIC;
       m_tlast  : out STD_LOGIC;
       m_tready : in  STD_LOGIC
       );
end volume_controller;

architecture Behavioral of volume_controller is

    -------------------------- CONSTANTS ----------------------------
    -- 'Normalizzazione' delle Generic inserite dall'utente, d'ora in poi verranno utilizzate solo queste
    -- Le richieste dell'uternte in termini di volume massimo e minimo possono essere descritte da soli due parametri interi
    -- (ad esempio Neutro e Massimo, come in questo caso). La terza generic è una ridondanza che abbiamo preferito inserire per 
    -- tenere una maggiore fedeltà alla consegna. 
    
    constant VOL_HIGH : INTEGER := VOLUME_MAX     - VOLUME_MIN;
    constant VOL_NEUT : INTEGER := VOLUME_DEFAULT - VOLUME_MIN;
    
    -- Lunghezza del vettore 'check'
    constant CHECK_LENGTH : INTEGER := VOL_HIGH - VOL_NEUT;  
    -----------------------------------------------------------------
    
    ---------------------------- SIGNALS ----------------------------
    -- E' il volume, 0 corrisponde a VOLUME_MIN
    signal volume                     : INTEGER RANGE 0 TO VOL_HIGH := VOL_NEUT;
    -- Servono per controllare la saturazione
    signal check, check_source        : UNSIGNED ( CHECK_LENGTH-1 DOWNTO 0 ); 
    -- Axis
    signal s_tready_int, m_tvalid_int : STD_LOGIC := '0';
    
    -- Segnali necessari alla pipeline
    -- La flag data_in serve per gestire il traffico tra i due stadi in maniera più efficiente 
    signal data_in    : STD_LOGIC;
    signal volume_pip : INTEGER RANGE 0 TO VOL_HIGH;
    signal data_pip   : STD_LOGIC_VECTOR ( s_tdata'RANGE );
    signal last_pip   : STD_LOGIC := '0';
    -----------------------------------------------------------------

begin

    --------------------------- DATA FLOW ---------------------------
    m_tvalid     <= m_tvalid_int;
    
    s_tready     <= s_tready_int;
    
    s_tready_int <= '0' when ( m_tvalid_int = '1' and m_tready = '0' ) or rst = '1' else '1';
    
    
    -- Generazione del vettore di controllo controllando gli MSB in funzione del volume, se il numero è:
    -- positivo: controllo che ci siano '1' 
    -- negativo: controllo che ci siano '0'
    inv_gen: 
    for i in CHECK_LENGTH-1 DOWNTO 0 generate 
       check_source(i) <= s_tdata(DATA_WIDTH-1) xor s_tdata( (DATA_WIDTH -2) + i - (CHECK_LENGTH-1) );   
    end generate;
    -----------------------------------------------------------------
    
    --------------------------- PROCESS -----------------------------
    process (clk, rst)              
    begin
        ----- ASYNC -----
        -- Controllo LEDs in codice termometrico 
        volume_level  <= (Others => '0');             
        volume_level(volume DOWNTO 0)  <= (Others => '1'); 
        
        if rst = '1' then
            volume          <= VOL_NEUT;    
            m_tvalid_int    <= '0';
            
        ----- SYNC -----
        elsif rising_edge (clk) then
        
        
            -- Controllo del volume UP/DOWN
            if  volume_up = '1' and volume /= VOL_HIGH then
                volume <= volume +1;
            end if;
            if  volume_down = '1' and volume /= 0 then
                volume <= volume -1;
            end if;
            
            
            -- Controllo AXIS di uscita
            if m_tvalid_int ='1' and m_tready ='1' then 
                m_tvalid_int <= '0';    -- eventualmente verrà sovrascritto
            end if;
            
            
            -- Secondo stadio della pipeline
            -- Nel codice il secondo stadio è stato scritto prima del primo stadio, per lasciare 
            -- la possibilità di sovrascrittura di data_in
            if data_in = '1' and s_tready_int = '1' then
                
                data_in      <= '0'; -- eventualmente verrà sovrascritto
                m_tvalid_int <= '1';
                m_tlast      <= last_pip;
                
                if volume_pip > VOL_NEUT then
                
                    -- Moltiplicazione
                    if check = 0 then 
                        -- Se 'check' (vettore) è composto da soli zeri, allora non c'è saturazione 
                        m_tdata <= STD_LOGIC_VECTOR(shift_left(SIGNED(data_pip), volume_pip - VOL_NEUT)); 
                    else 
                        -- Se 'check' contiene almeno un '1', saturazione      
                        m_tdata(DATA_WIDTH-2 downto 0) <= (Others => not(data_pip(DATA_WIDTH-1)));  
                        m_tdata(DATA_WIDTH-1) <= data_pip(DATA_WIDTH-1);
                    end if;
                    
                else
                
                    -- Divisione
                    m_tdata <= STD_LOGIC_VECTOR( shift_right(SIGNED(data_pip), VOL_NEUT - volume_pip )); 
                    
                end if; 

            end if;
            
            
            -- Primo stadio della pipeline
            if s_tvalid = '1' and s_tready_int = '1' then
                
                data_in    <= '1';     
                data_pip   <= s_tdata;   
                last_pip   <= s_tlast;
                volume_pip <= volume; 
                
                -- Check del possibile overflow   
                -- soltanto i MSB necessari in funzione del volume vengono presi in considerazione 
                check <= resize(check_source(CHECK_LENGTH-1 DOWNTO VOL_HIGH - volume), check'LENGTH);      
                
            end if; 
            
            
        end if; 
    end process;
    -----------------------------------------------------------------
    
end Behavioral;
