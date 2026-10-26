-- =============================================================================
-- Decodificador binário para one-hot parametrizável
--
-- Converte um índice binário de largura num_inputs em um vetor one-hot de
-- 2^num_inputs bits, onde apenas o bit correspondente ao valor numérico de
-- i_d vale '1' e todos os demais valem '0'.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

entity onehot_decoder is
	
	generic (
		-- Largura do endereço binário de entrada (em bits).
		num_inputs : natural := 3
	);
	
	port (
		-- Endereço binário de entrada.
		i_d : in  std_logic_vector((num_inputs-1) downto 0);
		-- Vetor one-hot decodificado de saída (2^num_inputs bits).
		o_d : out std_logic_vector(((2**num_inputs)-1) downto 0)
	);
	
end entity;

architecture rtl of onehot_decoder is

  -- Sinal para as entradas e suas versoes invertidas
  signal not_d : std_logic_vector((num_inputs-1) downto 0);
  
begin

  -- Gera as versoes invertidas de cada bit de entrada
  not_d <= not i_d;
  
  -- Para cada saida 'i', cria uma porta AND
  gen_decoder : for i in 0 to ((2**num_inputs)-1) generate
    
    -- Sinal temporario para a saida da porta AND
    signal and_gate_out : std_logic_vector(num_inputs-1 downto 0);
	 
	 -- Sinal para a cadeia de reducao AND
    signal and_reduction_chain : std_logic_vector(num_inputs-1 downto 0);
	 
	 begin

    -- Logica para cada bit do AND:
    gen_and_inputs : for j in 0 to (num_inputs-1) generate
      and_gate_out(j) <= i_d(j) when (((i / (2**j)) mod 2) = 1) else not_d(j);
    end generate;
	 
    -- Inicia a cadeia AND com o primeiro bit
    and_reduction_chain(0) <= and_gate_out(0);
    
    -- Reduz o vetor 'and_gate_out' a um unico bit
    gen_and_reduction : for j in 1 to (num_inputs-1) generate
      and_reduction_chain(j) <= and_reduction_chain(j-1) and and_gate_out(j);
    end generate;
    
    -- A saida do decoder e o resultado final da cadeia de reducao
    o_d(i) <= and_reduction_chain(num_inputs-1);
    
  end generate;
	
end architecture;