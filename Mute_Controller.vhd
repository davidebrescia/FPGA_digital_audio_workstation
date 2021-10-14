---------------------------------------------------------------------------------------------------------------
-- mute_controller
--
-- Sincrono, per migliorare il critical path
---------------------------------------------------------------------------------------------------------------

---------- DEFAULT LIBRARY ---------
library IEEE;
	use IEEE.STD_LOGIC_1164.all;
	use IEEE.NUMERIC_STD.ALL;
------------------------------------

entity mute_controller is
    Generic (
        -- Larghezza di tdata
        DATA_WIDTH : INTEGER := 16
    );
    Port ( 
       clk : in     STD_LOGIC;
       rst : in     STD_LOGIC;
       
       mute_left  : in STD_LOGIC;
       mute_right : in STD_LOGIC;
       
       s_tdata  : in  STD_LOGIC_VECTOR ( DATA_WIDTH-1 DOWNTO 0 );
       s_tvalid : in  STD_LOGIC;
       s_tlast  : in  STD_LOGIC;
       s_tready : out STD_LOGIC;
       
       m_tdata  : out STD_LOGIC_VECTOR ( DATA_WIDTH-1 DOWNTO 0 );
       m_tvalid : out STD_LOGIC;
       m_tlast  : out STD_LOGIC;
       m_tready : in  STD_LOGIC
       );
end mute_controller;

architecture Behavioral of mute_controller is

    -------------------------- CONSTANTS ----------------------------
    constant MUTE_VALUE : STD_LOGIC_VECTOR ( m_tdata'RANGE ) := ( OTHERS => '0');
    -----------------------------------------------------------------

    ---------------------------- SIGNALS ----------------------------
    signal s_tready_int, m_tvalid_int            : STD_LOGIC := '0';
    signal mute_left_sampled, mute_right_sampled : STD_LOGIC;   
    -----------------------------------------------------------------
    
begin

    --------------------------- DATA FLOW ---------------------------    
    m_tvalid     <= m_tvalid_int;
    
    s_tready     <= s_tready_int;
    s_tready_int <= '0' when ( m_tvalid_int = '1' and m_tready = '0' ) or rst = '1' else '1';
    -----------------------------------------------------------------
 
    --------------------------- PROCESS -----------------------------
    process (clk, rst)
    begin
        ----- ASYNC -----
        if rst = '1' then
            m_tvalid_int <= '0';
        
        ----- SYNC -----
        elsif rising_edge(clk) then
            
            -- Sampling dei segnali asincroni 
            mute_left_sampled  <= mute_left;
            mute_right_sampled <= mute_right;
            
            -- Axis
            if m_tvalid_int ='1' and m_tready = '1' then 
                m_tvalid_int <= '0'; 
            end if;
            
            -- Mute controller 
            if s_tvalid = '1' and s_tready_int = '1' then
               
               m_tvalid_int <= '1';
               m_tlast      <= s_tlast;
               
               if  ( mute_left_sampled  = '1' and s_tlast = '0' ) or 
                   ( mute_right_sampled = '1' and s_tlast = '1' ) then
                    m_tdata <= MUTE_VALUE;
               else
                    m_tdata <= s_tdata; 
               end if;
               
           end if;
           
        end if;
    end process;
    -----------------------------------------------------------------

end Behavioral;
