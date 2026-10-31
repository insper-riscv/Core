# Banco de Registradores na FPGA (DE0-CV)

🌐 [Português](README.md) · [English](README.en.md)

Teste interativo em placa (DE0-CV) para o banco de registradores RV32I ($32 \times 32$ bits), operado diretamente por chaves (`SW`), botões (`KEY`, `FPGA_RESET_N`), LEDs (`LEDR`) e displays de 7 segmentos (`HEX`).

[![Demonstração do Banco de Registradores (Vídeo em Português)](https://img.youtube.com/vi/6z75OKjMnCE/0.jpg)](https://youtu.be/6z75OKjMnCE?si=i_e1n5RB_PhHB0rD)

## 1. Funcionamento

1. O clock do banco de registradores é um pulso único gerado por um detector de borda a partir de `FPGA_RESET_N` (ativo em nível baixo); cada acionamento do botão produz exatamente 1 ciclo de clock e efetiva a escrita configurada nas chaves na borda de subida.
2. O registrador `x0` permanece fixo em zero ($x_0 = 0$); leituras no endereço `0` retornam `0` e escritas no endereço `0` são descartadas.
3. Os endereços de leitura A e B e de escrita C são selecionados pelas chaves no intervalo $0..3$ (com os bits superiores fixos em zero no topo de teste).

## 2. Mapeamento de Entrada e Saída

### 2.1. Entradas

| Pino | Sinal / Função |
| :--- | :--- |
| `SW[9]` | Habilitação de escrita no próximo pulso de clock (`1` habilita escrita) |
| `SW[8:6]` | Dado de escrita de 3 bits, estendido com zeros para 32 bits |
| `SW[5:4]` | Endereço de escrita C (2 bits menos significativos, estendido com zeros para 5 bits) |
| `SW[3:2]` | Endereço de leitura B (2 bits menos significativos) |
| `SW[1:0]` | Endereço de leitura A (2 bits menos significativos) |
| `KEY[0]` | Reset assíncrono do banco (ativo em nível baixo, invertido antes da entrada de clear) |
| `FPGA_RESET_N` | Botão de passo de clock (ativo em nível baixo, gera 1 pulso via detector de borda) |

### 2.2. Saídas

| Pino | Sinal Exibido |
| :--- | :--- |
| `HEX0` | Endereço de leitura A |
| `HEX1` | Endereço de leitura B |
| `HEX2` | Nibble inferior (`[3:0]`) do dado lido na porta A |
| `HEX3` | Nibble inferior (`[3:0]`) do dado lido na porta B |
| `HEX4` | Nibble de escrita (`'0' & SW[8:6]`) |
| `HEX5` | Endereço de escrita C |
| `LEDR[0]` | Estado de `SW[9]` (habilitação de escrita) |
| `LEDR[1]` | Estado de `not KEY[0]` (clear ativo) |
| `LEDR[2]` | Estado de `not FPGA_RESET_N` (botão de passo pressionado) |
| `LEDR[3]` | Clock de 50 MHz da placa (`CLOCK_50`, referência visual) |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../../LICENSE).
