//+------------------------------------------------------------------+
//|                                  XAUUSD_Engulfing_Bajista_v2.mq5 |
//|                        Indicador Engulfing Bajista XAU/USD M1   |
#property copyright "PatronM1 System"
#property version   "8.00"
#property description "Engulfing Bajista XAU/USD M1 — Indicador Final"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// ═══════════════════════════════════════════════════════════════
// STAGE 3 — BACKTESTER INTEGRADO
// Analiza las ultimas N barras y calcula estadisticas reales
// ═══════════════════════════════════════════════════════════════

//--- Grupo: Gestión de Riesgo
input group "=== Gestión de Riesgo ==="
input double   InpCapital       = 5000.0;  // Capital de la cuenta (USD)
input double   InpRiskPct       = 1.0;     // Riesgo por operación (%)

//--- Grupo: Parámetros de Trade
input group "=== Parámetros de Trade ==="
input double   InpTP            = 10.0;    // Take Profit (pts en precio)
input double   InpSL            = 20.0;    // Stop Loss (pts en precio)
input int      InpMaxBars       = 5;       // Timeout: cerrar en N barras
input double   InpBETrigger     = 3.0;     // Breakeven: mover SL a N pts ganancia

//--- Grupo: Filtros del Patrón
input group "=== Filtros del Patrón ==="
input double   InpBodyMin       = 1.0;     // Cuerpo mínimo (pts) — sweet spot 1-4
input double   InpBodyMax       = 4.0;     // Cuerpo máximo (pts) — sweet spot 1-4
input double   InpPrevRangeMax  = 8.0;     // Rango máx barra previa (0 = sin filtro)
input bool     InpUseVolFilter  = true;    // Activar filtro de volumen
input int      InpVolPeriod     = 20;      // Período promedio de volumen
input double   InpVolMultiplier = 1.0;     // Volumen > promedio × multiplicador

//--- Grupo: Backtester
input group "=== Backtester Integrado ==="
input int      InpLookback      = 10000;   // Barras hacia atrás para analizar

//--- Grupo: Panel y Alertas
input group "=== Panel y Alertas ==="
input bool     InpShowPanel     = true;    // Mostrar panel informativo
input string   InpPanelFont     = "Arial"; // Fuente del panel
input int      InpPanelFontSize = 8;       // Tamaño de fuente
input bool     InpAlertSound    = true;    // Alerta sonora
input bool     InpAlertPush     = false;   // Alerta push notification

//--- Variables globales
datetime lastAlertTime = 0;
int totalSignals = 0;     // Todas las envolventes bajistas (sin filtros)
int filteredSignals = 0;  // Las que pasan TODOS los filtros
double currentLotSize = 0; // Lotaje para la ultima senal filtrada

//--- Variables del backtester integrado (Stage 3)
int btWins = 0;
int btLosses = 0;
int btBreakevens = 0;
double btPnL = 0;
double btMaxDD = 0;
int btMaxWinStreak = 0;
int btMaxLossStreak = 0;
int btCurWinStreak = 0;   // Racha ganadora actual
int btCurLossStreak = 0;  // Racha perdedora actual
double btAccByHour[24];  // Contador de ops por hora
double btAccWins[24];    // Wins por hora
bool btDone = false;     // Para ejecutar el backtester solo una vez

//--- Totales persistentes del backtester (para que no se borren en cada tick)
int btTotalSignals = 0;
int btFilteredSignals = 0;
datetime btStartDate = 0;  // Fecha de la primera barra analizada
datetime btEndDate = 0;    // Fecha de la última barra analizada

// ═══════════════════════════════════════════════════════════════
// STAGE 2 — FILTRO HORARIO + ACCURACY POR HORA
// Basado en ALLINFO.md Seccion 1 (Estadisticas) y Seccion 4 (Indicador)
// ═══════════════════════════════════════════════════════════════

//--- Accuracy% por hora del servidor (UTC+2)
// Calculada sobre 646 señales cerradas del backtest
double AccByHour(int h)
{
   // Indices 0-23 = horas del servidor UTC+2
   double acc[] = {
      84.6,  // 00:00 srv
      85.2,  // 01:00 srv
      86.7,  // 02:00 srv
      69.2,  // 03:00 srv — HORA DEBIL
      92.9,  // 04:00 srv
      91.7,  // 05:00 srv
      100.0, // 06:00 srv — MEJOR HORA
      93.8,  // 07:00 srv
      75.0,  // 08:00 srv — HORA DEBIL (apertura Londres)
      75.9,  // 09:00 srv — HORA DEBIL
      95.8,  // 10:00 srv
      88.9,  // 11:00 srv
      94.7,  // 12:00 srv
      88.5,  // 13:00 srv
      84.8,  // 14:00 srv
      91.7,  // 15:00 srv
      84.9,  // 16:00 srv
      78.9,  // 17:00 srv
      78.6,  // 18:00 srv
      88.0,  // 19:00 srv
      88.9,  // 20:00 srv
      87.5,  // 21:00 srv
      66.7,  // 22:00 srv — PEOR HORA
      85.6   // 23:00 srv (default)
   };
   if(h >= 0 && h < 24) return acc[h];
   return 85.6;  // default
}

//--- Color segun accuracy de la hora
color AccColor(double acc)
{
   if(acc >= 90) return clrLimeGreen;   // ★ PREMIUM
   if(acc >= 80) return clrDodgerBlue;  // BUENA
   if(acc >= 70) return clrOrange;      // REGULAR
   return clrRed;                        // DEBIL
}

//--- Texto de calidad segun accuracy
string AccQuality(double acc)
{
   if(acc >= 90) return "PREMIUM";
   if(acc >= 80) return "BUENA";
   if(acc >= 70) return "REGULAR";
   return "DEBIL";
}

// ═══════════════════════════════════════════════════════════════
// STAGE 3 — SIMULACION FORWARD (Backtester integrado)
// ═══════════════════════════════════════════════════════════════

//--- Valor del punto en USD por lote (calculo universal)
double g_pointValue = 100.0;  // Se calcula en OnInit
int    g_digits = 2;          // Dígitos del símbolo
double g_point = 0.01;        // _Point del símbolo

double GetPointValuePerLot()
{
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize > 0) return tickVal / tickSize;
   return 100.0;  // fallback para XAU/USD estandar
}

//--- Simula un trade forward (compartido entre backtester y tooltip)
// Retorna: 1=WIN, -1=LOSS, 0=BE o FLAT
int SimulateForward(const double &open[], const double &high[], const double &low[],
                    const double &close[], int rates_total, int barIdx,
                    double entry, double tp, double sl, double beTrigger, int maxBars,
                    double &outExit, double &outPnlPts, int &outBars, bool &outHitBE,
                    bool &outTimeout)
{
   double tpPrice = entry - tp;
   double slPrice = entry + sl;
   double bePrice = entry - beTrigger;
   bool hitBE = false;
   bool closed = false;
   double exitPrice = 0;
   bool isWin = false;
   int barsUsed = 0;

   for(int f = 1; f <= maxBars && (barIdx - f) >= 0; f++)
   {
      barsUsed = f;
      if(low[barIdx - f] <= bePrice) hitBE = true;
      if(high[barIdx - f] >= slPrice)
      {
         exitPrice = slPrice; isWin = false; closed = true; break;
      }
      if(low[barIdx - f] <= tpPrice)
      {
         exitPrice = tpPrice; isWin = true; closed = true; break;
      }
   }
   if(!closed)
   {
      int closeIdx = barIdx - maxBars;
      if(closeIdx < 0) closeIdx = 0;
      exitPrice = close[closeIdx];
      isWin = (exitPrice < entry);
   }

   double pnlPts = entry - exitPrice;
   bool finalBE = (hitBE && !isWin && pnlPts < 0);
   if(finalBE) { pnlPts = 0; exitPrice = entry; }

   outExit = exitPrice;
   outPnlPts = pnlPts;
   outBars = barsUsed;
   outHitBE = hitBE;
   outTimeout = !closed;

   if(finalBE) return 0;
   return isWin ? 1 : -1;
}

//--- Funcion principal: escanea y simula trades en las ultimas lookback barras
void RunBacktester(const datetime &time[],
                   const double &open[],
                   const double &high[],
                   const double &low[],
                   const double &close[],
                   const long &tick_volume[],
                   int rates_total,
                   int lookback,
                   double tp, double sl, int maxBars,
                   double bodyMin, double bodyMax, double rangeMax,
                   bool useVol, int volPeriod, double volMult,
                   double beTrigger, double capital, double riskPct)
{
   // Resetear contadores
   btWins = 0;
   btLosses = 0;
    btBreakevens = 0;
    btPnL = 0;
    btMaxDD = 0;
   btMaxWinStreak = 0;
   btMaxLossStreak = 0;
   ArrayInitialize(btAccByHour, 0);
   ArrayInitialize(btAccWins, 0);

   double riskDollar = capital * (riskPct / 100.0);
   double slDollarPerLot = sl * g_pointValue;
   double lots = riskDollar / slDollarPerLot;

   double equity = capital;
   double peak = capital;
   int curWinStreak = 0;
   int curLossStreak = 0;
   int btTotalCount = 0;
   int btFilteredCount = 0;

    // Escanear las ultimas 'lookback' barras (las mas recientes)
    // En modo series: indice 0 es la mas reciente.
    // Analizamos desde la barra 'lookback' hacia atras hasta la barra 1.
    int startBar = MathMin(lookback, rates_total - 2);
    int endBar = 1;

    for(int i = startBar; i >= endBar; i--)
   {
      // --- Detectar patron engulfing bajista ---
      bool prev_bull   = (close[i+1] > open[i+1]);
      bool curr_bear   = (close[i] < open[i]);
      bool open_above  = (open[i] > close[i+1]);
      bool close_below = (close[i] < open[i+1]);

      if(!prev_bull || !curr_bear || !open_above || !close_below)
         continue;

      btTotalCount++;

      // --- Filtros ---
      double body_curr  = open[i] - close[i];
      double range_prev = high[i+1] - low[i+1];

      bool body_ok = (body_curr >= bodyMin && body_curr <= bodyMax);
      bool no_spike = (rangeMax == 0.0) || (range_prev <= rangeMax);

      bool vol_ok = true;
      if(useVol)
      {
         long vol_sum = 0;
         int vol_count = 0;
         for(int j = 1; j <= volPeriod && (i+j) < rates_total; j++)
         {
            vol_sum += tick_volume[i+j];
            vol_count++;
         }
         if(vol_count > 0)
         {
            double vol_avg = (double)vol_sum / vol_count;
            vol_ok = (tick_volume[i] >= vol_avg * volMult);
         }
      }

      if(!body_ok || !no_spike || !vol_ok)
         continue;

      btFilteredCount++;

      // --- Senal valida: simular forward (funcion compartida) ---
      double entry = close[i];
      double tpPrice = entry - tp;
      double slPrice = entry + sl;
      double bePrice = entry - beTrigger;

      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int h = dt.hour;

      double exitPrice = 0, pnlPts = 0;
      int barsUsed = 0;
      bool hitBE = false, isTimeout = false;

      int result = SimulateForward(open, high, low, close, rates_total, i,
                                   entry, tp, sl, beTrigger, maxBars,
                                   exitPrice, pnlPts, barsUsed, hitBE, isTimeout);

      double pnlDollar = pnlPts * lots * g_pointValue;
      bool finalIsBE = (result == 0);
      if(finalIsBE) pnlDollar = 0;

      // Actualizar contadores
      btAccByHour[h]++;

      if(finalIsBE)
      {
         btBreakevens++;
         btPnL += pnlDollar;
      }
      else if(result == 1)
      {
         btWins++;
         curWinStreak++;
         curLossStreak = 0;
         btMaxWinStreak = MathMax(btMaxWinStreak, curWinStreak);
         btPnL += pnlDollar;
         btAccWins[h]++;
      }
      else
      {
         btLosses++;
         curLossStreak++;
         curWinStreak = 0;
         btMaxLossStreak = MathMax(btMaxLossStreak, curLossStreak);
         btPnL += pnlDollar;
      }

      // Equity curve y max drawdown
      equity += pnlDollar;
      peak = MathMax(peak, equity);
      double dd = (peak - equity) / peak * 100.0;
      btMaxDD = MathMax(btMaxDD, dd);
   }

    // Guardar rachas actuales (las ultimas procesadas = mas recientes)
    btCurWinStreak = curWinStreak;
    btCurLossStreak = curLossStreak;

    // Guardar totales persistentes (para que no se borren en cada tick)
    btTotalSignals = btTotalCount;
    btFilteredSignals = btFilteredCount;
    
    // Guardar rango de fechas analizado
    // startBar = barra más antigua en el rango (índice alto)
    // endBar = barra más reciente en el rango (índice bajo)
    btStartDate = time[startBar];
    btEndDate = time[endBar];
    
    // Log
    PrintBacktestResults();
}

//+------------------------------------------------------------------+
//| Inicializacion del indicador                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Detección automática de parámetros del símbolo ---
   g_pointValue = GetPointValuePerLot();
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   Print("=== Engulfing Bajista v4.0 ===");
   Print("Símbolo: ", _Symbol);
   Print("_Point: ", g_point, " | Dígitos: ", g_digits);
   Print("Valor/punto/lot: $", DoubleToString(g_pointValue, 2));

   // ═══════════════════════════════════════════════════════
   // STAGE 6 — CHECKLIST DE VALIDACION
   // ═══════════════════════════════════════════════════════
   string warnings = "";

   // 1. TP y SL no intercambiados
   if(InpTP > InpSL)
      warnings += "[WARN] TP > SL — ratio riesgo/beneficio invertido\n";

   // 2. Body min/max en rango logico
   if(InpBodyMin > InpBodyMax)
      warnings += "[WARN] BodyMin > BodyMax — filtro nunca pasara\n";
   if(InpBodyMin == 0 && InpBodyMax == 0)
      warnings += "[WARN] BodyMin=0 y BodyMax=0 — sin filtro de cuerpo\n";

   // 3. Riesgo excesivo
   if(InpRiskPct > 2.0)
      warnings += "[WARN] Riesgo > 2% — alto para cuenta real\n";

   // 4. MaxBars muy alto
   if(InpMaxBars > 10)
      warnings += "[WARN] MaxBars > 10 — timeout muy largo\n";

   // 5. Lookback muy bajo
   if(InpLookback < 1000)
      warnings += "[WARN] Lookback < 1000 — estadisticas poco confiables\n";

   // 6. PrevRangeMax = 0 (sin filtro)
   if(InpPrevRangeMax == 0)
      warnings += "[INFO] PrevRangeMax=0 — sin filtro de spike\n";

   // 7. Volumen desactivado
   if(!InpUseVolFilter)
      warnings += "[INFO] VolFilter OFF — sin filtro de volumen\n";

   if(warnings != "")
   {
      Print("=== VALIDATION WARNINGS ===");
      Print(warnings);
   }
   else
   {
      Print("=== VALIDATION: ALL CHECKS PASSED ===");
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Engulfing Bajista XAU/USD M1 v4.0");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Funcion principal — se ejecuta en cada barra                     |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],    // No usado — obligatorio por firma MQL5
                const int &spread[])     // No usado — obligatorio por firma MQL5
{
   //--- Necesitamos al menos 2 barras para detectar el patron
   if(rates_total < 2)
      return(0);

   //--- Poner arrays en modo series: [0] = barra mas reciente
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(tick_volume, true);

   //--- Determinar desde donde empezar a escanear
   // Si es la primera vez, escanear todo. Si no, solo las barras nuevas.
   int start = (prev_calculated == 0) ? rates_total - 2 : rates_total - prev_calculated + 1;

   //--- Resetear contadores
   totalSignals = 0;
   filteredSignals = 0;

   // ─────────────────────────────────────────────────────────────
   // BUCLE PRINCIPAL — recorrer todas las barras del chart
   // ─────────────────────────────────────────────────────────────
   for(int i = start; i >= 0; i--)
   {
      // Necesitamos la barra actual [i] y la previa [i+1]
      if(i + 1 >= rates_total) continue;

      // ═══════════════════════════════════════════════════════
      // STAGE 4a: Pre-patron (vela alcista que podria ser engullida)
      // ═══════════════════════════════════════════════════════
      // Condiciones: vela alcista + cuerpo en rango + hora IN (Acc >= 80%)
      // Solo se dibuja si la SIGUIENTE vela [i-1] fue un engulfing

      bool curr_bull   = (close[i] > open[i]);
      double body_bull = close[i] - open[i];
      MqlDateTime dtPre;
      TimeToStruct(time[i], dtPre);
      double accPre = AccByHour(dtPre.hour);

      // Verificar si la siguiente vela [i-1] fue un engulfing bajista
      // Reutilizamos curr_bull (ya calculado arriba) en vez de recalcular
      bool next_is_engulfing = false;
      if(i > 0)
      {
         bool n_bear   = (close[i-1] < open[i-1]);
         bool n_open   = (open[i-1] > close[i]);
         bool n_close  = (close[i-1] < open[i]);
         next_is_engulfing = (curr_bull && n_bear && n_open && n_close);
      }

      // Solo dibujar pre-signal si la siguiente vela fue engulfing
      if(curr_bull && body_bull >= InpBodyMin && body_bull <= InpBodyMax && accPre >= 80.0 && next_is_engulfing)
      {
         string preName = StringFormat("EngV2_Pre_%d", i);
         if(ObjectFind(0, preName) < 0)
         {
            // Circulo amarillo debajo del low (codigo 159)
            ObjectCreate(0, preName, OBJ_ARROW, 0, time[i], low[i] - 0.30);
            ObjectSetInteger(0, preName, OBJPROP_ARROWCODE, 159);
            ObjectSetInteger(0, preName, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, preName, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, preName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, preName, OBJPROP_HIDDEN, true);

            string preTooltip = StringFormat("[ PRE-PATRON ]\n"
                                             "Vela alcista en hora %s (Acc %.1f%%)\n"
                                             "Body: $%.2f\n"
                                             "La siguiente vela SI engullo -> SENAL SHORT",
                                             AccQuality(accPre), accPre, body_bull);
            ObjectSetString(0, preName, OBJPROP_TOOLTIP, preTooltip);
         }
      }
      else
      {
         // Si no se cumple, eliminar pre-signal si existe
         string preName = StringFormat("EngV2_Pre_%d", i);
         if(ObjectFind(0, preName) >= 0)
            ObjectDelete(0, preName);
      }

      // ═══════════════════════════════════════════════════════
      // PASO 1: Detectar patron Engulfing Bajista (base)
      // ═══════════════════════════════════════════════════════

      // Condicion 1: la barra previa [i+1] debe ser ALCISTA
      bool prev_bull = (close[i+1] > open[i+1]);

      // Condicion 2: la barra actual [i] debe ser BAJISTA
      bool curr_bear = (close[i] < open[i]);

      // Condicion 3: la barra actual abre POR ENCIMA del cierre previo
      bool open_above = (open[i] > close[i+1]);

      // Condicion 4: la barra actual cierra POR DEBAJO de la apertura previa
      bool close_below = (close[i] < open[i+1]);

      // Si no cumple las 4 condiciones basicas, no es engulfing bajista
      if(!prev_bull || !curr_bear || !open_above || !close_below)
         continue;

      // Contamos TODAS las envolventes (sin filtros)
      totalSignals++;

      // ═══════════════════════════════════════════════════════
      // PASO 2: Aplicar filtros del patron
      // ═══════════════════════════════════════════════════════

      // --- Calcular cuerpo de la vela senal (en precio directo USD) ---
      double body_curr = open[i] - close[i];  // positivo porque es vela bajista

      // --- Calcular rango de la vela previa ---
      double range_prev = high[i+1] - low[i+1];

      // --- Filtro de cuerpo minimo y maximo ---
      // Sweet spot del backtest: 1-4 pts → 92-95% accuracy
      // Cuerpo > 8 pts: evitar (solo 73.7% acc)
      bool body_ok = (body_curr >= InpBodyMin && body_curr <= InpBodyMax);

      // --- Filtro de rango de la vela previa (no-spike) ---
      // Si la barra anterior fue muy grande, hay riesgo de gap/spike
      // Valor 0 = desactivar este filtro
      bool no_spike = (InpPrevRangeMax == 0.0) || (range_prev <= InpPrevRangeMax);

      // --- Filtro de volumen ---
      // El volumen de la vela senal debe ser mayor al promedio de InpVolPeriod barras
      bool vol_ok = true;
      if(InpUseVolFilter)
      {
         // Calcular promedio de volumen de las ultimas InpVolPeriod barras
         long vol_sum = 0;
         int vol_count = 0;
         for(int j = 1; j <= InpVolPeriod && (i+j) < rates_total; j++)
         {
            vol_sum += tick_volume[i+j];
            vol_count++;
         }

         if(vol_count > 0)
         {
            double vol_avg = (double)vol_sum / vol_count;
            vol_ok = (tick_volume[i] >= vol_avg * InpVolMultiplier);
         }
      }

      // --- Verificar si pasa TODOS los filtros ---
      bool all_filters_ok = body_ok && no_spike && vol_ok;

      // ═══════════════════════════════════════════════════════
      // PASO 2b: Obtener hora y accuracy dinamica (STAGE 2)
      // ═══════════════════════════════════════════════════════

      // Obtener hora del servidor de la barra actual
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int h_server = dt.hour;

      // Obtener accuracy de esta hora (tabla del backtest)
      double acc = AccByHour(h_server);
      color  col_base  = AccColor(acc);
      string calidad   = AccQuality(acc);

      // ═══════════════════════════════════════════════════════
      // PASO 3: Dibujar flecha (SIEMPRE, con distincion visual)
      // ═══════════════════════════════════════════════════════
      // - Filtrada: flecha del color de accuracy (verde/azul/naranja/rojo)
      // - No filtrada: flecha gris pequena y tenue

      if(all_filters_ok)
      {
         filteredSignals++;
         // Calcular lotaje para esta senal (Stage 7)
         double riskDollar = InpCapital * (InpRiskPct / 100.0);
         currentLotSize = riskDollar / (InpSL * g_pointValue);
         // Redondear a 2 decimales y respetar limites del broker
         currentLotSize = MathRound(currentLotSize * 100.0) / 100.0;
         double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
         currentLotSize = MathMax(lotMin, MathMin(lotMax, currentLotSize));
      }

      // Nombre unico para cada objeto
      string arrowName = StringFormat("EngV2_Arrow_%d", i);

      if(ObjectFind(0, arrowName) < 0)
      {
         // Determinar color y tamano segun estado
         color arrowColor;
         int   arrowWidth;

         if(all_filters_ok)
         {
            // Pasa filtros → color segun accuracy de la hora
            arrowColor = col_base;
            arrowWidth = 3;
         }
         else
         {
            // No pasa filtros → gris tenue
            arrowColor = clrDarkGray;
            arrowWidth = 1;
         }

         ObjectCreate(0, arrowName, OBJ_ARROW, 0, time[i], high[i] + 0.30);
         ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, 234);
         ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
         ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, arrowWidth);
         ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
      }

      // ═══════════════════════════════════════════════════════
      // STAGE 4b/4c: Lineas TP/SL/Entry desde la senal filtrada
      // ═══════════════════════════════════════════════════════
      if(all_filters_ok)
      {
         double entry = close[i];
         double tpPrice = entry - InpTP;
         double slPrice = entry + InpSL;

         // Calcular tiempo final de las lineas (InpMaxBars adelante)
         int endIdx = i - InpMaxBars;
         if(endIdx < 0) endIdx = 0;
         datetime tEnd = time[endIdx];

         // Linea TP (verde punteada)
         string tpName = StringFormat("EngV2_TP_%d", i);
         if(ObjectFind(0, tpName) < 0)
         {
            ObjectCreate(0, tpName, OBJ_TREND, 0, time[i], tpPrice, tEnd, tpPrice);
            ObjectSetInteger(0, tpName, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, tpName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, tpName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, tpName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, tpName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, tpName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, tpName, OBJPROP_BACK, true);
         }

         // Linea SL (roja punteada)
         string slName = StringFormat("EngV2_SL_%d", i);
         if(ObjectFind(0, slName) < 0)
         {
            ObjectCreate(0, slName, OBJ_TREND, 0, time[i], slPrice, tEnd, slPrice);
            ObjectSetInteger(0, slName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, slName, OBJPROP_STYLE, STYLE_DASH);
            ObjectSetInteger(0, slName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, slName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, slName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, slName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, slName, OBJPROP_BACK, true);
         }

         // Linea de entrada (amarilla solida, al close de la vela)
         string entryName = StringFormat("EngV2_Entry_%d", i);
         if(ObjectFind(0, entryName) < 0)
         {
            ObjectCreate(0, entryName, OBJ_TREND, 0, time[i], entry, tEnd, entry);
            ObjectSetInteger(0, entryName, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, entryName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, entryName, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, entryName, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, entryName, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, entryName, OBJPROP_HIDDEN, true);
            ObjectSetInteger(0, entryName, OBJPROP_BACK, true);
         }
      }

      // --- Tooltip con info detallada ---
      string status = all_filters_ok
         ? StringFormat("★ FILTRADA | Hora %02d:00 | Acc %.1f%% | %s", h_server, acc, calidad)
         : StringFormat("✗ NO FILTRADA | Hora %02d:00 | Acc %.1f%%", h_server, acc);

      string failReason = "";
      if(!all_filters_ok)
      {
         if(!body_ok)    failReason += "  - Body fuera de rango ($" + DoubleToString(InpBodyMin,1) + "-$" + DoubleToString(InpBodyMax,1) + ")\n";
         if(!no_spike)   failReason += "  - Prev range alto ($" + DoubleToString(range_prev,2) + " > $" + DoubleToString(InpPrevRangeMax,1) + ")\n";
         if(!vol_ok)     failReason += "  - Volumen bajo\n";
      }

      // --- Simular resultado forward para el tooltip ---
      string tradeResult = "N/A";
      string tradeDetail = "";
      if(all_filters_ok)
      {
         double entry = close[i];
         double tpPrice = entry - InpTP;
         double slPrice = entry + InpSL;
         double bePrice = entry - InpBETrigger;
         double exitPrice = 0, pnlPts = 0;
         int barsUsed = 0;
         bool hitBE = false, isTimeout = false;

         int result = SimulateForward(open, high, low, close, rates_total, i,
                                      entry, InpTP, InpSL, InpBETrigger, InpMaxBars,
                                      exitPrice, pnlPts, barsUsed, hitBE, isTimeout);

         double riskDollar = InpCapital * (InpRiskPct / 100.0);
         double lots = riskDollar / (InpSL * g_pointValue);
         double pnlDollar = pnlPts * lots * g_pointValue;

         if(result == 0)
            tradeResult = StringFormat("BREAKEVEN (BE activado a %.2f)", bePrice);
         else if(isTimeout)
            tradeResult = StringFormat("TIMEOUT (%d barras) | PnL: %+.1f pts | $%+.2f", barsUsed, pnlPts, pnlDollar);
         else if(result == 1)
            tradeResult = StringFormat("WIN (TP en %.2f) | +%d pts | +$%.2f", tpPrice, (int)InpTP, riskDollar);
         else
            tradeResult = StringFormat("LOSS (SL en %.2f) | -%d pts | -$%.2f", slPrice, (int)InpSL, riskDollar);

         tradeDetail = StringFormat("Entry: %.2f | TP: %.2f | SL: %.2f | BE: %.2f", entry, tpPrice, slPrice, bePrice);
      }

      string tooltip = StringFormat("=== ENGULFING BAJISTA ===\n"
                                    "%s\n"
                                    "Fecha: %s %02d:%02d UTC+2\n"
                                    "Open: %.2f | Close: %.2f\n"
                                    "High: %.2f | Low: %.2f\n"
                                    "Body: $%.2f\n"
                                    "Prev range: $%.2f\n"
                                    "Volumen: %d",
                                    status,
                                    TimeToString(time[i], TIME_DATE), dt.hour, dt.min,
                                    open[i], close[i],
                                    high[i], low[i],
                                    body_curr,
                                    range_prev,
                                    tick_volume[i]);

      if(tradeResult != "N/A")
         tooltip += StringFormat("\n\n--- Resultado Simulado ---\n%s\n%s", tradeResult, tradeDetail);

      if(!all_filters_ok && failReason != "")
         tooltip += "\n\nFiltros que fallo:\n" + failReason;

      ObjectSetString(0, arrowName, OBJPROP_TOOLTIP, tooltip);

      // --- Alerta solo en barra actual (solo si pasa filtros) ---
      if(i == 0 && all_filters_ok && time[i] != lastAlertTime)
      {
         lastAlertTime = time[i];
         string alertMsg = StringFormat("★ ENGULFING FILTRADO %s | %02d:%02d UTC+2 | Acc: %.1f%% | Body: $%.2f",
                                        calidad, dt.hour, dt.min, acc, body_curr);
         if(InpAlertSound) Alert(alertMsg);
         if(InpAlertPush) SendNotification(alertMsg);
      }
   }

   // ─────────────────────────────────────────────────────────────
   // STAGE 3: Ejecutar backtester integrado (solo una vez)
   // ─────────────────────────────────────────────────────────────
   if(!btDone && rates_total >= InpLookback)
   {
      RunBacktester(time, open, high, low, close, tick_volume,
                    rates_total, InpLookback,
                    InpTP, InpSL, InpMaxBars,
                    InpBodyMin, InpBodyMax, InpPrevRangeMax,
                    InpUseVolFilter, InpVolPeriod, InpVolMultiplier,
                    InpBETrigger, InpCapital, InpRiskPct);
      btDone = true;
   }

   // ─────────────────────────────────────────────────────────────
   // Dibujar panel informativo (si esta activado)
   // ─────────────────────────────────────────────────────────────
   if(InpShowPanel)
      DrawPanel(rates_total, prev_calculated);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Dibuja el panel de informacion en el chart                       |
//| Optimizado: solo actualiza textos, no recrea objetos             |
//+------------------------------------------------------------------+
void DrawPanel(int rates_total, int prev_calculated)
{
   string prefix = "EngV2_Panel_";
   string font = InpPanelFont;
   int fs = InpPanelFontSize;

   // --- Fondo del panel (solo crear si no existe) ---
   string bg = prefix + "BG";
   if(ObjectFind(0, bg) < 0)
   {
      ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, bg, OBJPROP_XSIZE, 280);
      ObjectSetInteger(0, bg, OBJPROP_YSIZE, 320);
      ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bg, OBJPROP_COLOR, clrDarkGray);
      ObjectSetInteger(0, bg, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bg, OBJPROP_BACK, false);
      ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   }

    // --- Hora actual y datos ---
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int h_srv = dt.hour;
    
    // --- Parte 1: Calcular horas adyacentes (con wrap-around) ---
    int h_prev = (h_srv - 1 + 24) % 24;
    int h_next = (h_srv + 1) % 24;

    // Calcular WR dinamico del backtester
    double dynWR = (btWins + btLosses > 0) ? (double)btWins / (btWins + btLosses) * 100 : 0;
    double dynAcc = (btAccByHour[h_srv] > 0) ? btAccWins[h_srv] / btAccByHour[h_srv] * 100 : AccByHour(h_srv);

    // --- Parte 2: Calcular Accuracies adyacentes ---
    double prevAcc = (btAccByHour[h_prev] > 0) ? btAccWins[h_prev] / btAccByHour[h_prev] * 100 : AccByHour(h_prev);
    double nextAcc = (btAccByHour[h_next] > 0) ? btAccWins[h_next] / btAccByHour[h_next] * 100 : AccByHour(h_next);
   string dynInOut = (dynAcc >= 80.0) ? "IN" : "OUT";
   color dynInOutClr = (dynAcc >= 80.0) ? clrLime : clrRed;
   string dynQuality = AccQuality(dynAcc);
   color dynQualityClr = AccColor(dynAcc);

    // --- Labels: solo actualizar texto (no recrear) ---
    SetLabel(prefix + "L1", 15, 36, "Bear Engulfing M1", clrWhite, fs+1, font, true);
    // Usar totales persistentes del backtester si ya se ejecutó
    int displayTotal = btDone ? btTotalSignals : totalSignals;
    int displayFiltered = btDone ? btFilteredSignals : filteredSignals;
    SetLabel(prefix + "L2", 15, 56, StringFormat("Totals: %d", displayTotal), clrGray, fs, font, false);
    SetLabel(prefix + "L3", 15, 76, StringFormat("Filtered: %d", displayFiltered), clrLime, fs, font, true);
   SetLabel(prefix + "L4", 15, 94,
      StringFormat("Time: %02d:%02d | Acc: %.1f%% | %s", h_srv, dt.min, dynAcc, dynInOut),
      dynInOutClr, fs, font, true);
   SetLabel(prefix + "L5", 15, 112,
      StringFormat("Quality: %s", dynQuality),
      dynQualityClr, fs, font, false);

   double riskDollar = InpCapital * (InpRiskPct / 100.0);
   if(filteredSignals > 0)
      SetLabel(prefix + "L6", 15, 130,
         StringFormat("Lot: %.2f | Risk: $%.0f (%.1f%%)", currentLotSize, riskDollar, InpRiskPct),
         clrAqua, fs, font, true);
   else
      SetLabel(prefix + "L6", 15, 130,
         StringFormat("Lot: -- | Risk: $%.0f (%.1f%%)", riskDollar, InpRiskPct),
         clrDarkGray, fs, font, false);

   SetLabel(prefix + "L7", 15, 148,
      StringFormat("WR: %.1f%% | W:%d L:%d | BE:%d", dynWR, btWins, btLosses, btBreakevens),
      clrYellow, fs-1, font, false);

   color pnlClr = (btPnL >= 0) ? clrLime : clrRed;
   SetLabel(prefix + "L8", 15, 166,
      StringFormat("PnL: $%+.0f | DD: %.1f%%", btPnL, btMaxDD),
      pnlClr, fs-1, font, false);

   SetLabel(prefix + "L9", 15, 184,
      StringFormat("Max Streaks: W:%d L:%d", btMaxWinStreak, btMaxLossStreak),
      clrDarkGray, fs-1, font, false);

   string curStreakText = "";
   color curStreakClr = clrDarkGray;
   if(btCurWinStreak > 0)
   {
      curStreakText = StringFormat("Current: +%d wins", btCurWinStreak);
      curStreakClr = clrLime;
   }
   else if(btCurLossStreak > 0)
   {
      curStreakText = StringFormat("Current: -%d losses", btCurLossStreak);
      curStreakClr = clrRed;
   }
   else
      curStreakText = "Current: 0 (sin racha)";
   SetLabel(prefix + "L10", 15, 202, curStreakText, curStreakClr, fs-1, font, false);

   string wickStatus = (InpPrevRangeMax > 0) ? "Yes" : "No";
   SetLabel(prefix + "L11", 15, 220,
      StringFormat("Wick: %s | Lookback: %d", wickStatus, InpLookback),
      clrDarkGray, fs-1, font, false);
   
    // L15: Accuracies adyacentes (Prev | Curr | Next)
    string accLine = StringFormat("Acc: [%02d]: %.0f%% | [%02d]: %.0f%% | [%02d]: %.0f%%", 
                                  h_prev, prevAcc, h_srv, dynAcc, h_next, nextAcc);
    SetLabel(prefix + "L15", 15, 280, accLine, clrDarkGray, fs-1, font, false);

    // L13: Rango de fechas del backtest
   if(btDone && btStartDate > 0)
   {
      string sStart = StringSubstr(TimeToString(btStartDate, TIME_DATE), 8, 2) + "/" + StringSubstr(TimeToString(btStartDate, TIME_DATE), 5, 2);
      string sEnd   = StringSubstr(TimeToString(btEndDate, TIME_DATE), 8, 2) + "/" + StringSubstr(TimeToString(btEndDate, TIME_DATE), 5, 2);
      SetLabel(prefix + "L13", 15, 240, StringFormat("I: %s | F: %s", sStart, sEnd), clrDarkGray, fs-1, font, false);
   }
   else
   {
      SetLabel(prefix + "L13", 15, 240, "I:-- | F:--", clrDarkGray, fs-1, font, false);
   }
   
   // L14: Versión (antes L12)
   SetLabel(prefix + "L14", 15, 260, "Final v8.0", clrDarkGray, fs-2, font, false);
   
   string btnName = prefix + "BtnRefresh";
   if(ObjectFind(0, btnName) < 0)
   {
    ObjectCreate(0, btnName, OBJ_BUTTON, 0, 0, 0);
    ObjectSetString(0, btnName, OBJPROP_TEXT, "Reset");
    ObjectSetInteger(0, btnName, OBJPROP_XDISTANCE, 15);
     ObjectSetInteger(0, btnName, OBJPROP_YDISTANCE, 300);
    ObjectSetInteger(0, btnName, OBJPROP_XSIZE, 120);
    ObjectSetInteger(0, btnName, OBJPROP_YSIZE, 25);
    ObjectSetInteger(0, btnName, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, btnName, OBJPROP_BGCOLOR, clrDodgerBlue);
    ObjectSetInteger(0, btnName, OBJPROP_BORDER_COLOR, clrBlue);
    ObjectSetInteger(0, btnName, OBJPROP_SELECTABLE, false);
    ObjectSetString(0, btnName, OBJPROP_FONT, "Arial Bold");
   }
}

//+------------------------------------------------------------------+
//| Helper: crear o actualizar label (solo cambia texto si existe)   |
//+------------------------------------------------------------------+
void SetLabel(string name, int x, int y, string text, color clr, int fontSize, string font, bool bold)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? (font + " Bold") : font);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Limpieza al remover el indicador del chart                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "EngV2_Arrow_");
   ObjectsDeleteAll(0, "EngV2_Pre_");
   ObjectsDeleteAll(0, "EngV2_TP_");
   ObjectsDeleteAll(0, "EngV2_SL_");
   ObjectsDeleteAll(0, "EngV2_Entry_");
   ObjectsDeleteAll(0, "EngV2_Panel_");
}

void OnChartEvent(const int id,const long& lparam,const double& dparam,const string& sparam)
  {
   // Detectar clic en objeto refresh
   if(id == CHARTEVENT_OBJECT_CLICK && sparam == "EngV2_Panel_BtnRefresh")
   {
    Print("===> Solicitud de recarga Backtest");
    
    // Reset flag
    btDone = false;
    
    // Limpiar panel
    ObjectsDeleteAll(0, "EngV2_Panel_");
    
    // Forzar recalculo completo
    ChartSetSymbolPeriod(0, _Symbol, _Period);
    
    Print("===> Backtest recargando...");
   }
  }

//+------------------------------------------------------------------+

void PrintBacktestResults()
{
    Print("========= Backtest =========");
    Print("Periodo: ", TimeToString(btStartDate, TIME_DATE), " > ", TimeToString(btEndDate, TIME_DATE));
    Print("Patrones Totales: ", btTotalSignals, " | Filtrados: ", btFilteredSignals);

    int totalOps = btWins + btLosses + btBreakevens;
    
    double wr = (totalOps > 0) ? ((double)btWins/totalOps) * 100 : 0;
    double lr = (totalOps > 0) ? ((double)btLosses/totalOps) * 100 : 0;
    double br = (totalOps > 0) ? ((double)btBreakevens/totalOps) * 100 : 0;
    
    Print("Total Operaciones: ", totalOps);
    Print("Win rate:", DoubleToString(wr,1), "% (",btWins,")");
    Print("Loss rate:", DoubleToString(lr,1), "% (",btLosses,")");
    Print("BreakEven rate:", DoubleToString(br,1), "% (",btBreakevens,")");
    Print("PnL: $", DoubleToString(btPnL,2));
    
    Print("--Accuracy per hour--");
    for(int h=0;h<24;h++)
      {
       if(btAccByHour[h]>0)
       {
       double acc = btAccWins[h] / btAccByHour[h] * 100;
       Print("Hora ", h,": ", DoubleToString(acc, 1), "% (", (int)btAccByHour[h], " ops )");
       }
      }
      
    Print("============================");
}
