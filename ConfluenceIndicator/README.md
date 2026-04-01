# Confluence_v1 - MT5 Indicator

Indicador de confluencia multi-timeframe para MetaTrader 5. Combina análisis de tendencia (EMAs), estructura de mercado (Swings) y detección de entradas automatizada.

## Características

- **3 EMAs**: 9 (naranja), 21 (roja), 50 (azul)
- **Detección de Swings**: Highs y Lows con filtro alternante (H-L-H-L) para evitar señales falsas
- **Multi-Timeframe**: Análisis fijo en H1 (configurable) + CTF (Current TimeFrame)
- **Líneas de nivel**: Trazado desde el swing hasta tiempo actual con colores AFT/contra-tendencia
- **Confluencias**: Detecta Round Numbers (RN), niveles .50 (R50), Prev Day High/Low (PDH/PDL)
- **Señales de entrada**: Ruptura de niveles clave en CTF alineados con tendencia H1

## Inputs

| Parámetro | Default | Descripción |
|-----------|---------|-------------|
| `InpEmaFast` | 9 | Periodo EMA rápida |
| `InpEmaMedium` | 21 | Periodo EMA media |
| `InpEmaSlow` | 50 | Periodo EMA lenta |
| `InpAnalysisTF` | H1 | Timeframe de análisis principal |
| `InpSwingLookbackH1` | 5 | Velas para detectar swings en H1 |
| `InpSwingLookbackCTF` | 5 | Velas para detectar swings en CTF |
| `InpMaxSwingLinesH1` | 6 | Máx. líneas dibujadas en H1 |
| `InpMaxSwingLinesCTF` | 6 | Máx. líneas dibujadas en CTF |
| `InpEntrySignals` | true | Activar/desactivar señales de entrada |
| `InpTPRatio` | 2.0 | Ratio riesgo:beneficio para TP |

## Cómo leer los Labels

### H1 / CTF
- **A Im**: Tendencia alcista + Impulso (HH+HL)
- **A Pb**: Tendencia alcista + Retroceso (LH+HL)
- **B Im**: Tendencia bajista + Impulso (LL+LH)
- **B Pb**: Tendencia bajista + Retroceso (HH+LL)
- **RA / RB**: Rango con dirección alcista/bajista

### Entry Label
- **No setup**: Sin señal válida
- **B**: BUY - `E:entrada SL:stop TP:takeprofit`
- **S**: SELL - `E:entrada SL:stop TP:takeprofit`

## Lógica de Entrada

1. **H1 debe estar en tendencia** (A o B, no Rango)
2. **El precio en CTF debe romper AMBAS líneas** del último swing:
   - **BUY**: Cierre > SwingLowLine Y Cierre > SwingHighLine
   - **SELL**: Cierre < SwingHighLine Y Cierre < SwingLowLine
3. **SL**: Línea opuesta del swing
4. **TP**: Riesgo × InpTPRatio (default 2:1)

## Setup Recomendado para Testing

- **Timeframe**: M5 o M15 para entradas, H4 para contexto
- **Pares**: EURUSD, GBPUSD, XAUUSD (buena estructura de swings)
- **Lookback**: H1=5, CTF=3 (más rápido en CTF para timing)
- **Filtrar**: Operar solo cuando H1 muestra `Im` (impulso), evitar `Pb` en contra
