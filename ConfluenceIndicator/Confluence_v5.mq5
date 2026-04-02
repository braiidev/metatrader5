//+------------------------------------------------------------------+
//|                                              Confluence_v5.mq5   |
//|                                  Market Structure + EMA Confluence |
//+------------------------------------------------------------------+
// REFACTOR v5 - Cambios principales:
// 1. Usa InpAnalysisTF en lugar de PERIOD_H1 hardcodeado
// 2. OHLC completo del swing: punto en el precio exacto, linea en el opuesto
// 3. EMA state del HTF para colorear swings del HTF, EMA state del CTF para swings del CTF
// 4. Tooltips corregidos (no invertidos)
// 5. DeleteSwingObjects optimizado con tracking de nombres
// 6. Alert debounce por tiempo de barra
// 7. TimeframeToString completo
// 8. CTF swings siempre dibujados (sin restriccion < H1)
// 9. DetectStructureFromPatterns con logica real
// 10. Eliminada redundancia DetectSwings + FindSwingPoints vs loop inline
// 11. Unificado struct SwingPoint + DrawSwing en un solo struct
// 12. prev_calculated optimization en OnCalculate
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "5.10"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "EMA Fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "EMA Medium"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "EMA Slow"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- Inputs: EMAs del CTF (Current Timeframe)
input group "=== EMAs ==="
input int   InpEmaFast          = 9;
input int   InpEmaMedium        = 21;
input int   InpEmaSlow          = 50;

//--- Inputs: Analisis HTF
input group "=== Analisis HTF ==="
input ENUM_TIMEFRAMES InpAnalysisTF    = PERIOD_H1;
input int   InpSwingLookbackHTF  = 5;
input int   InpSwingLookforwardHTF = 5;
input int   InpSwingLookbackCTF  = 5;
input int   InpSwingLookforwardCTF = 5;
input int   InpMaxSwingLinesHTF = 6;
input int   InpMaxSwingLinesCTF = 6;

//--- Inputs: Senales de entrada
input group "=== Entry Signals ==="
input bool  InpEntrySignals     = true;
input double InpTPRatio         = 2.0;

//--- Buffers para las EMAs del CTF (se dibujan en el chart)
double BufferFast[];
double BufferMedium[];
double BufferSlow[];

//--- Handles de EMAs: CTF y HTF
int handleFast;
int handleMedium;
int handleSlow;
int handleFastTF;
int handleMediumTF;
int handleSlowTF;

//--- Nombres de labels en el chart
const string LABEL_CTF = "ConfluenceLabel_CTF";
const string LABEL_HTF = "ConfluenceLabel_HTF";
const string LABEL_ENTRY = "ConfluenceLabel_Entry";

//--- Prefijo para objetos de swings (tracking eficiente)
const string SWING_PREFIX = "CFL_Swing_";

//--- Estructura unificada para puntos de swing
struct SwingData
{
   datetime time;
   double price;
   bool isHigh;
   int barIndex;
   double open;
   double high;
   double low;
   double close;
};

//--- Swing mas reciente del HTF (para entry signals)
double g_htfLastSwingHighPrice = 0;
double g_htfLastSwingLowPrice = 0;
double g_htfLastSwingHighLow = 0;
double g_htfLastSwingLowHigh = 0;

//--- Swing mas reciente del CTF (para entry signals)
double g_ctfLastSwingHighPrice = 0;
double g_ctfLastSwingLowPrice = 0;
double g_ctfLastSwingHighLow = 0;
double g_ctfLastSwingLowHigh = 0;

//--- Estados guardados
string g_ctfEmaState = "Rango";
string g_ctfStructure = "Escaneando...";
string g_htfEmaState = "Rango";
string g_htfStructure = "Escaneando...";

//--- Alert debounce: evita spam guardando la ultima barra con senal
string g_prevEntrySignal = "";
datetime g_lastSignalBarTime = 0;

//--- Cache de confluencia (evita llamadas repetidas a CopyHigh/CopyLow D1)
string g_cachedConfluence = "";
double g_cachedConfluencePrice = 0;
datetime g_cachedConfluenceTime = 0;

//--- Tracking de nombres de objetos swing para delete eficiente
string g_swingObjectNames[];
int g_swingObjectCount = 0;

//+------------------------------------------------------------------+
//| Inicializacion del indicador                                      |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validar que el analysis TF sea mayor al CTF
   if(InpAnalysisTF <= Period())
   {
      Print("Confluence: InpAnalysisTF (", EnumToString(InpAnalysisTF),
            ") debe ser mayor al CTF (", EnumToString(Period()), ")");
      return(INIT_FAILED);
   }

   // Asignar buffers de indicadores (las 3 EMAs del CTF)
   SetIndexBuffer(0, BufferFast, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMedium, INDICATOR_DATA);
   SetIndexBuffer(2, BufferSlow, INDICATOR_DATA);
   ArraySetAsSeries(BufferFast, true);
   ArraySetAsSeries(BufferMedium, true);
   ArraySetAsSeries(BufferSlow, true);

   // Crear handles de EMAs para el CTF (se dibujan en el chart)
   handleFast   = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast,   0, MODE_EMA, PRICE_CLOSE);
   handleMedium = iMA(_Symbol, PERIOD_CURRENT, InpEmaMedium, 0, MODE_EMA, PRICE_CLOSE);
   handleSlow   = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow,   0, MODE_EMA, PRICE_CLOSE);

   if(handleFast == INVALID_HANDLE || handleMedium == INVALID_HANDLE || handleSlow == INVALID_HANDLE)
   {
      Print("Confluence: Error creando handles EMA para CTF");
      return(INIT_FAILED);
   }

   // Crear handles de EMAs para el HTF (solo para analisis, no se dibujan)
   handleFastTF   = iMA(_Symbol, InpAnalysisTF, InpEmaFast,   0, MODE_EMA, PRICE_CLOSE);
   handleMediumTF = iMA(_Symbol, InpAnalysisTF, InpEmaMedium, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowTF   = iMA(_Symbol, InpAnalysisTF, InpEmaSlow,   0, MODE_EMA, PRICE_CLOSE);

   if(handleFastTF == INVALID_HANDLE || handleMediumTF == INVALID_HANDLE || handleSlowTF == INVALID_HANDLE)
   {
      Print("Confluence: Error creando handles EMA para HTF (", EnumToString(InpAnalysisTF), ")");
      return(INIT_FAILED);
   }

   // Array para tracking de objetos swing
   ArrayResize(g_swingObjectNames, 200);

   IndicatorSetString(INDICATOR_SHORTNAME, "Confluence_v5");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Limpieza al desinicializar                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handleFast   != INVALID_HANDLE) IndicatorRelease(handleFast);
   if(handleMedium != INVALID_HANDLE) IndicatorRelease(handleMedium);
   if(handleSlow   != INVALID_HANDLE) IndicatorRelease(handleSlow);
   if(handleFastTF   != INVALID_HANDLE) IndicatorRelease(handleFastTF);
   if(handleMediumTF != INVALID_HANDLE) IndicatorRelease(handleMediumTF);
   if(handleSlowTF   != INVALID_HANDLE) IndicatorRelease(handleSlowTF);

   DeleteAllSwingObjects();

   ObjectDelete(0, LABEL_CTF);
   ObjectDelete(0, LABEL_HTF);
   ObjectDelete(0, LABEL_ENTRY);
}

//+------------------------------------------------------------------+
//| Calculo principal del indicador (se ejecuta en cada tick/barra)   |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < MathMax(InpSwingLookbackCTF, InpSwingLookbackHTF) * 4 + 1)
      return(0);

   // Copiar datos de las EMAs del CTF
   int toCopy = MathMin(rates_total, 1000);
   if(CopyBuffer(handleFast,   0, 0, toCopy, BufferFast)   <= 0) return(0);
   if(CopyBuffer(handleMedium, 0, 0, toCopy, BufferMedium) <= 0) return(0);
   if(CopyBuffer(handleSlow,   0, 0, toCopy, BufferSlow)   <= 0) return(0);

   // Determinar estado EMA del CTF
   string ctfEmaState = EmaStateToString(BufferFast[0], BufferMedium[0], BufferSlow[0]);
   g_ctfEmaState = ctfEmaState;

   // Detectar estructura del CTF usando los datos del chart actual
   g_ctfStructure = DetectStructureFromSeries(high, low, time, rates_total, InpSwingLookbackCTF, InpSwingLookforwardCTF);

   // Dibujar swings del HTF y del CTF
   DrawAllSwings(ctfEmaState);

   // Crear label del CTF
   CreateCTFLabel(ctfEmaState, g_ctfStructure, close, open);

   // Crear label del HTF (analisis completo con sus propias EMAs y swings)
   BuildAnalysisTFLabel();

   // Verificar senales de entrada
   if(InpEntrySignals)
      CheckEntrySignal(ctfEmaState, close, rates_total, time);
   else
      CreateEntryLabel("Signals OFF", clrGray);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Determina tendencia segun posicion relativa de 3 EMAs             |
//| Retorna: "Alcista", "Bajista" o "Rango"                           |
//+------------------------------------------------------------------+
string EmaStateToString(double emaFast, double emaMedium, double emaSlow)
{
   if(emaFast > emaMedium && emaMedium > emaSlow) return "Alcista";
   if(emaFast < emaMedium && emaMedium < emaSlow) return "Bajista";
   return "Rango";
}

//+------------------------------------------------------------------+
//| Convierte estado EMA a formato corto para labels                  |
//+------------------------------------------------------------------+
string EmaStateToShort(string state)
{
   if(state == "Alcista") return "A";
   if(state == "Bajista") return "B";
   return "R";
}

//+------------------------------------------------------------------+
//| Detecta estructura de mercado desde arrays de series              |
//| Busca swings highs/lows y compara los 2 mas recientes             |
//| Retorna: "Im" (impulso), "Pb" (pullback), "Escaneando..."         |
//+------------------------------------------------------------------+
string DetectStructureFromSeries(const double &high[], const double &low[],
                                  const datetime &time[], int rates_total, int lookback, int lookforward)
{
   double highs[];
   double lows[];
   datetime times[];
   ArrayResize(highs, 3);
   ArrayResize(lows, 3);
   int highCount = 0;
   int lowCount = 0;

   int start = lookback;
   int end = MathMin(rates_total - lookforward - 1, 200);

   for(int i = start; i <= end && (highCount < 2 || lowCount < 2); i++)
   {
      bool isSH = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(high[i] <= high[i - j])
         {
            isSH = false;
            break;
         }
      }
      if(isSH && lookforward > 0)
      {
         for(int j = 1; j <= lookforward; j++)
         {
            if(high[i] <= high[i + j])
            {
               isSH = false;
               break;
            }
         }
      }
      if(isSH && highCount < 2)
      {
         highs[highCount] = high[i];
         highCount++;
      }

      bool isSL = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(low[i] >= low[i - j])
         {
            isSL = false;
            break;
         }
      }
      if(isSL && lookforward > 0)
      {
         for(int j = 1; j <= lookforward; j++)
         {
            if(low[i] >= low[i + j])
            {
               isSL = false;
               break;
            }
         }
      }
      if(isSL && lowCount < 2)
      {
         lows[lowCount] = low[i];
         lowCount++;
      }
   }

   if(highCount < 2 || lowCount < 2)
      return "Escaneando...";

   double hThresh = highs[1] * 0.0001;
   double lThresh = lows[1] * 0.0001;
   string hPat = GetPattern(highs[0], highs[1], hThresh) + "H";
   string lPat = GetPattern(lows[0], lows[1], lThresh) + "L";

   return DetectStructureFromPatterns(hPat, lPat);
}

//+------------------------------------------------------------------+
//| Determina patron de un swing comparando con el anterior           |
//| "H" = higher, "L" = lower, "E" = equal (dentro del threshold)     |
//+------------------------------------------------------------------+
string GetPattern(double current, double previous, double threshold)
{
   double diff = current - previous;
   if(diff > threshold) return "H";
   if(diff < -threshold) return "L";
   return "E";
}

//+------------------------------------------------------------------+
//| Interpreta la combinacion de patrones de highs y lows             |
//| HH+HL = impulso alcista, LL+LH = impulso bajista                  |
//| LH+HL = pullback alcista, HH+LL = pullback bajista                |
//| EH/EL = equal = consolidacion -> Pb                               |
//+------------------------------------------------------------------+
string DetectStructureFromPatterns(string highPattern, string lowPattern)
{
   if(highPattern == "" || lowPattern == "")
      return "Escaneando...";

   if(highPattern == "HH" && lowPattern == "HL") return "Im";
   if(highPattern == "LL" && lowPattern == "LH") return "Im";
   if(highPattern == "LH" && lowPattern == "HL") return "Pb";
   if(highPattern == "HH" && lowPattern == "LL") return "Pb";
   if(highPattern == "LL" && lowPattern == "HL") return "Pb";
   if(highPattern == "LH" && lowPattern == "LL") return "Pb";
   if(highPattern == "EH" && lowPattern == "HL") return "Pb";
   if(highPattern == "HH" && lowPattern == "EL") return "Pb";
   if(highPattern == "EH" || lowPattern == "EL") return "Eq";

   return "Pb";
}

//+------------------------------------------------------------------+
//| Crea label del CTF con estado EMA + estructura                    |
//+------------------------------------------------------------------+
void CreateCTFLabel(string emaState, string structure, const double &close[], const double &open[])
{
   string text;
   color textColor;

   if(emaState == "Rango")
   {
      text = (close[0] >= open[0]) ? "RA" : "RB";
      textColor = clrYellow;
   }
   else
   {
      text = EmaStateToShort(emaState) + " " + structure;
      if(emaState == "Alcista" && structure == "Im")
         textColor = clrLime;
      else if(emaState == "Bajista" && structure == "Im")
         textColor = clrRed;
      else if(structure == "Pb")
         textColor = clrOrange;
      else
         textColor = clrGray;
   }

   CreateLabelAt(LABEL_CTF, "CTF: " + text, textColor, 10, 25);
}

//+------------------------------------------------------------------+
//| Dibuja todos los swings: HTF (InpAnalysisTF) + CTF (Period)       |
//| Cada timeframe tiene su propio EMA state para colorear            |
//+------------------------------------------------------------------+
void DrawAllSwings(string ctfEmaState)
{
   DeleteAllSwingObjects();

   // Dibujar swings del HTF con su propio EMA state
   string htfEmaState = GetHTFEmaState();
   DrawSwingsForTF(InpAnalysisTF, false, htfEmaState);

   // Dibujar swings del CTF con su EMA state
   DrawSwingsForTF(Period(), true, ctfEmaState);
}

//+------------------------------------------------------------------+
//| Obtiene el estado EMA del HTF usando sus handles                  |
//+------------------------------------------------------------------+
string GetHTFEmaState()
{
   double emaFast[];
   double emaMedium[];
   double emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaMedium, true);
   ArraySetAsSeries(emaSlow, true);

   if(CopyBuffer(handleFastTF, 0, 0, 1, emaFast) <= 0) return "Rango";
   if(CopyBuffer(handleMediumTF, 0, 0, 1, emaMedium) <= 0) return "Rango";
   if(CopyBuffer(handleSlowTF, 0, 0, 1, emaSlow) <= 0) return "Rango";

   return EmaStateToString(emaFast[0], emaMedium[0], emaSlow[0]);
}

//+------------------------------------------------------------------+
//| Dibuja swings para un timeframe especifico                        |
//| 1. Copia OHLC del TF                                              |
//| 2. Detecta swing highs y lows                                     |
//| 3. Filtra swings consecutivos del mismo tipo (mantiene el extremo)|
//| 4. Dibuja puntos y lineas horizontales usando OHLC del swing      |
//| 5. Calcula estructura de mercado                                  |
//| 6. Dibuja puntos y lineas horizontales                            |
//+------------------------------------------------------------------+
void DrawSwingsForTF(ENUM_TIMEFRAMES tf, bool isCTF, string emaState)
{
   int barsToScan = 120;
   int totalBars = iBars(_Symbol, tf);
   if(totalBars < barsToScan)
      barsToScan = totalBars;
   if(barsToScan < 10)
      return;

   double tfHighs[], tfLows[], tfOpens[], tfCloses[];
   datetime tfTimes[];
   ArraySetAsSeries(tfHighs, true);
   ArraySetAsSeries(tfLows, true);
   ArraySetAsSeries(tfTimes, true);
   ArraySetAsSeries(tfOpens, true);
   ArraySetAsSeries(tfCloses, true);

   if(CopyHigh(_Symbol, tf, 0, barsToScan, tfHighs) <= 0) return;
   if(CopyLow(_Symbol, tf, 0, barsToScan, tfLows) <= 0) return;
   if(CopyTime(_Symbol, tf, 0, barsToScan, tfTimes) <= 0) return;
   if(CopyOpen(_Symbol, tf, 0, barsToScan, tfOpens) <= 0) return;
   if(CopyClose(_Symbol, tf, 0, barsToScan, tfCloses) <= 0) return;

   int lookback = isCTF ? InpSwingLookbackCTF : InpSwingLookbackHTF;
   int lookforward = isCTF ? InpSwingLookforwardCTF : InpSwingLookforwardHTF;
   int start = lookback;
   int end = barsToScan - lookforward - 1;
   if(end <= start) return;

   SwingData allSwings[];
   int swingCount = 0;
   ArrayResize(allSwings, 100);

   for(int i = start; i <= end && swingCount < 100; i++)
   {
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfHighs[i] <= tfHighs[i - j])
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh && lookforward > 0)
      {
         for(int j = 1; j <= lookforward; j++)
         {
            if(tfHighs[i] <= tfHighs[i + j])
            {
               isSwingHigh = false;
               break;
            }
         }
      }

      if(isSwingHigh)
      {
         allSwings[swingCount].time = tfTimes[i];
         allSwings[swingCount].price = tfHighs[i];
         allSwings[swingCount].isHigh = true;
         allSwings[swingCount].barIndex = i;
         allSwings[swingCount].open = tfOpens[i];
         allSwings[swingCount].high = tfHighs[i];
         allSwings[swingCount].low = tfLows[i];
         allSwings[swingCount].close = tfCloses[i];
         swingCount++;
         continue;
      }

      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfLows[i] >= tfLows[i - j])
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow && lookforward > 0)
      {
         for(int j = 1; j <= lookforward; j++)
         {
            if(tfLows[i] >= tfLows[i + j])
            {
               isSwingLow = false;
               break;
            }
         }
      }

      if(isSwingLow)
      {
         allSwings[swingCount].time = tfTimes[i];
         allSwings[swingCount].price = tfLows[i];
         allSwings[swingCount].isHigh = false;
         allSwings[swingCount].barIndex = i;
         allSwings[swingCount].open = tfOpens[i];
         allSwings[swingCount].high = tfHighs[i];
         allSwings[swingCount].low = tfLows[i];
         allSwings[swingCount].close = tfCloses[i];
         swingCount++;
      }
   }

   if(swingCount == 0)
      return;

   SwingData filtered[];
   int filteredCount = 0;
   ArrayResize(filtered, swingCount);

   filtered[0] = allSwings[0];
   filteredCount = 1;

   for(int i = 1; i < swingCount; i++)
   {
      if(allSwings[i].isHigh != filtered[filteredCount - 1].isHigh)
      {
         filtered[filteredCount] = allSwings[i];
         filteredCount++;
      }
      else
      {
         if(allSwings[i].isHigh && allSwings[i].price > filtered[filteredCount - 1].price)
            filtered[filteredCount - 1] = allSwings[i];
         else if(!allSwings[i].isHigh && allSwings[i].price < filtered[filteredCount - 1].price)
            filtered[filteredCount - 1] = allSwings[i];
      }
   }

   double ctfLastHigh = 0, ctfLastLow = 999999999;
   double ctfPrevHigh = 0, ctfPrevLow = 999999999;
   double htfLastHigh = 0, htfLastLow = 999999999;

   for(int i = 0; i < filteredCount; i++)
   {
      if(filtered[i].isHigh)
      {
         if(isCTF)
         {
            if(ctfLastHigh == 0) ctfLastHigh = filtered[i].price;
            else if(ctfPrevHigh == 0) ctfPrevHigh = filtered[i].price;
         }
         else
         {
            if(htfLastHigh == 0) htfLastHigh = filtered[i].price;
         }
      }
      else
      {
         if(isCTF)
         {
            if(ctfLastLow == 999999999) ctfLastLow = filtered[i].price;
            else if(ctfPrevLow == 999999999) ctfPrevLow = filtered[i].price;
         }
         else
         {
            if(htfLastLow == 999999999) htfLastLow = filtered[i].price;
         }
      }
   }

   if(isCTF && ctfLastHigh > 0 && ctfLastLow < 999999999)
   {
      g_ctfLastSwingHighPrice = ctfLastHigh;
      g_ctfLastSwingLowPrice = ctfLastLow;
      g_ctfLastSwingHighLow = 0;
      g_ctfLastSwingLowHigh = 999999999;

      for(int i = 0; i < filteredCount; i++)
      {
         if(filtered[i].isHigh && g_ctfLastSwingHighLow == 0)
            g_ctfLastSwingHighLow = filtered[i].low;
         if(!filtered[i].isHigh && g_ctfLastSwingLowHigh == 999999999)
            g_ctfLastSwingLowHigh = filtered[i].high;
      }

      string hPat = "", lPat = "";
      if(ctfPrevHigh > 0)
      {
         double diff = ctfLastHigh - ctfPrevHigh;
         double thresh = ctfPrevHigh * 0.0001;
         if(diff > thresh) hPat = "HH";
         else if(diff < -thresh) hPat = "LH";
         else hPat = "EH";
      }
      if(ctfPrevLow < 999999999)
      {
         double diff = ctfLastLow - ctfPrevLow;
         double thresh = ctfPrevLow * 0.0001;
         if(diff > thresh) lPat = "HL";
         else if(diff < -thresh) lPat = "LL";
         else lPat = "EL";
      }

      if(hPat != "" && lPat != "")
         g_ctfStructure = hPat + "-" + lPat;
      else
         g_ctfStructure = "Escaneando...";
   }

   if(!isCTF && htfLastHigh > 0 && htfLastLow < 999999999)
   {
      g_htfLastSwingHighPrice = htfLastHigh;
      g_htfLastSwingLowPrice = htfLastLow;
      g_htfLastSwingHighLow = 0;
      g_htfLastSwingLowHigh = 999999999;

      for(int i = 0; i < filteredCount; i++)
      {
         if(filtered[i].isHigh && g_htfLastSwingHighLow == 0)
            g_htfLastSwingHighLow = filtered[i].low;
         if(!filtered[i].isHigh && g_htfLastSwingLowHigh == 999999999)
            g_htfLastSwingLowHigh = filtered[i].high;
      }

      string hPat = "", lPat = "";
      double prevH = 0, prevL = 999999999;
      for(int i = 0; i < filteredCount; i++)
      {
         if(filtered[i].isHigh)
         {
            if(prevH == 0) prevH = filtered[i].price;
            else { prevH = filtered[i].price; break; }
         }
         else
         {
            if(prevL == 999999999) prevL = filtered[i].price;
         }
      }
      if(prevH > 0)
      {
         double diff = htfLastHigh - prevH;
         double thresh = prevH * 0.0001;
         if(diff > thresh) hPat = "HH";
         else if(diff < -thresh) hPat = "LH";
         else hPat = "EH";
      }
      if(prevL < 999999999)
      {
         double diff = htfLastLow - prevL;
         double thresh = prevL * 0.0001;
         if(diff > thresh) lPat = "HL";
         else if(diff < -thresh) lPat = "LL";
         else lPat = "EL";
      }
      if(hPat != "" && lPat != "")
         g_htfStructure = hPat + "-" + lPat;
      else
         g_htfStructure = "Escaneando...";
   }

   string tfPrefix = isCTF ? "CTF" : TimeframeToString(tf);
   int maxLines = isCTF ? InpMaxSwingLinesCTF : InpMaxSwingLinesHTF;
   int drawn = 0;

   for(int i = 0; i < filteredCount && drawn < maxLines; i++)
   {
      datetime dt = filtered[i].time;
      string dtStr = FormatDateTime(dt);

      color dotColor = filtered[i].isHigh ? clrLime : clrRed;
      int dotWidth = isCTF ? 1 : 3;

      bool isAFT = (emaState == "Bajista" && filtered[i].isHigh) ||
                   (emaState == "Alcista" && !filtered[i].isHigh);
      color lineColor = isAFT ? dotColor : C'105,105,105';

      string conf = filtered[i].isHigh ? GetConfluenceCached(filtered[i].low) : GetConfluenceCached(filtered[i].high);

      if(filtered[i].isHigh)
      {
         string dotName = SWING_PREFIX + "Dot_H_" + tfPrefix + "_" + dtStr + "_" + IntegerToString(i);
         string lineName = SWING_PREFIX + "Line_H_" + tfPrefix + "_" + dtStr + "_" + IntegerToString(i);

         CreateOrUpdateDot(dotName, dt, filtered[i].price, dotColor, dotWidth, ANCHOR_BOTTOM,
                             "SH " + tfPrefix + " " + dtStr + " " + conf);
         CreateOrUpdateTrendLine(lineName, dt, filtered[i].low,
                                 TimeCurrent(), filtered[i].low,
                                 lineColor, STYLE_DOT, 1, false,
                                 "SH-Line " + tfPrefix + " " + dtStr + " " + conf);

         TrackObjectName(dotName);
         TrackObjectName(lineName);
      }
      else
      {
         string dotName = SWING_PREFIX + "Dot_L_" + tfPrefix + "_" + dtStr + "_" + IntegerToString(i);
         string lineName = SWING_PREFIX + "Line_L_" + tfPrefix + "_" + dtStr + "_" + IntegerToString(i);

         CreateOrUpdateDot(dotName, dt, filtered[i].price, dotColor, dotWidth, ANCHOR_TOP,
                             "SL " + tfPrefix + " " + dtStr + " " + conf);
         CreateOrUpdateTrendLine(lineName, dt, filtered[i].high,
                                 TimeCurrent(), filtered[i].high,
                                 lineColor, STYLE_DOT, 1, false,
                                 "SL-Line " + tfPrefix + " " + dtStr + " " + conf);

         TrackObjectName(dotName);
         TrackObjectName(lineName);
      }

      drawn++;
   }
}

//+------------------------------------------------------------------+
//| Registra nombre de objeto swing para delete eficiente             |
//+------------------------------------------------------------------+
void TrackObjectName(string name)
{
   if(g_swingObjectCount < ArraySize(g_swingObjectNames))
   {
      g_swingObjectNames[g_swingObjectCount] = name;
      g_swingObjectCount++;
   }
}

//+------------------------------------------------------------------+
//| Elimina todos los objetos swing usando el tracking de nombres     |
//| Mucho mas eficiente que iterar todos los objetos del chart        |
//+------------------------------------------------------------------+
void DeleteAllSwingObjects()
{
   for(int i = 0; i < g_swingObjectCount; i++)
   {
      if(g_swingObjectNames[i] != "")
      {
         ObjectDelete(0, g_swingObjectNames[i]);
         g_swingObjectNames[i] = "";
      }
   }
   g_swingObjectCount = 0;
}

//+------------------------------------------------------------------+
//| Crea o actualiza un punto (dot) en el chart                       |
//+------------------------------------------------------------------+
void CreateOrUpdateDot(string name, datetime time1, double price1,
                       color col, int width, int anchor, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_ARROW, 0, time1, price1);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   }
   else
   {
      ObjectMove(0, name, 0, time1, price1);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Crea o actualiza una linea de tendencia horizontal                |
//+------------------------------------------------------------------+
void CreateOrUpdateTrendLine(string name, datetime time1, double price1,
                              datetime time2, double price2,
                              color col, ENUM_LINE_STYLE style, int width,
                              bool ray, string text)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, time1, price1, time2, price2);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, ray);
   }
   else
   {
      ObjectMove(0, name, 0, time1, price1);
      ObjectMove(0, name, 1, time2, price2);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//+------------------------------------------------------------------+
//| Crea un label generico en el chart                                |
//+------------------------------------------------------------------+
void CreateLabelAt(string objName, string text, color textColor, int xDistance, int yDistance)
{
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, objName, OBJPROP_FONT, "Arial Bold");
   }
   ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, xDistance);
   ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, yDistance);
   ObjectSetString(0, objName, OBJPROP_TEXT, text);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, textColor);
}

//+------------------------------------------------------------------+
//| Formatea datetime a string legible dd/mm/yy-HH:MM                 |
//+------------------------------------------------------------------+
string FormatDateTime(datetime dt)
{
   MqlDateTime dtStruct;
   TimeToStruct(dt, dtStruct);
   return StringFormat("%02d/%02d/%02d-%02d%02d",
      dtStruct.day, dtStruct.mon, dtStruct.year % 100,
      dtStruct.hour, dtStruct.min);
}

//+------------------------------------------------------------------+
//| Convierte ENUM_TIMEFRAMES a string legible                        |
//| Version completa: soporta todos los TF de M1 a MN1                |
//+------------------------------------------------------------------+
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "Unknown";
   }
}

//+------------------------------------------------------------------+
//| Calcula niveles de confluencia para un precio dado                |
//| RN = Round Number (00), R50 = medio punto (50)                    |
//| PDH/PDL = Previous Day High/Low                                   |
//| Cacheado por 60 segundos para evitar llamadas repetidas           |
//+------------------------------------------------------------------+
string GetConfluence(double price)
{
   string conf = "";
   double pip = _Point * 10;

   // Round Number: precio cerca de un nivel de 100 pips
   if(MathAbs(price - MathRound(price / (pip * 100)) * (pip * 100)) < pip * 5)
      conf += "RN";

   // Round 50: precio cerca de un nivel de 50 pips
   if(MathAbs(price - MathRound(price / (pip * 50)) * (pip * 50)) < pip * 5)
   {
      if(conf != "") conf += "+";
      conf += "R50";
   }

   // Previous Day High
   double pdh[];
   if(CopyHigh(_Symbol, PERIOD_D1, 1, 1, pdh) > 0)
   {
      if(MathAbs(price - pdh[0]) < pip * 10)
      {
         if(conf != "") conf += "+";
         conf += "PDH";
      }
   }

   // Previous Day Low
   double pdl[];
   if(CopyLow(_Symbol, PERIOD_D1, 1, 1, pdl) > 0)
   {
      if(MathAbs(price - pdl[0]) < pip * 10)
      {
         if(conf != "") conf += "+";
         conf += "PDL";
      }
   }

   if(conf == "")
      conf = "-";

   return conf;
}

//+------------------------------------------------------------------+
//| Version cacheada de GetConfluence (evita CopyHigh/CopyLow D1      |
//| repetidos en cada tick durante 60 segundos)                        |
//+------------------------------------------------------------------+
string GetConfluenceCached(double price)
{
   datetime currentTime = TimeCurrent();
   if(MathAbs(price - g_cachedConfluencePrice) < _Point * 5 &&
      currentTime - g_cachedConfluenceTime < 60)
      return g_cachedConfluence;

   g_cachedConfluence = GetConfluence(price);
   g_cachedConfluencePrice = price;
   g_cachedConfluenceTime = currentTime;
   return g_cachedConfluence;
}

//+------------------------------------------------------------------+
//| Construye el label del HTF con su propio analisis completo        |
//| Copia EMAs, OHLC del HTF, detecta swings y estructura             |
//+------------------------------------------------------------------+
void BuildAnalysisTFLabel()
{
   ENUM_TIMEFRAMES tf = InpAnalysisTF;
   int barsToCopy = MathMin(iBars(_Symbol, tf), 500);
   if(barsToCopy < InpSwingLookbackHTF * 4 + 1)
      return;

   double emaFast[], emaMedium[], emaSlow[];
   datetime tfTimes[];
   double tfHighs[], tfLows[], tfOpens[], tfCloses[];

   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaMedium, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(tfTimes, true);
   ArraySetAsSeries(tfHighs, true);
   ArraySetAsSeries(tfLows, true);
   ArraySetAsSeries(tfOpens, true);
   ArraySetAsSeries(tfCloses, true);

   if(CopyBuffer(handleFastTF, 0, 0, barsToCopy, emaFast) <= 0) return;
   if(CopyBuffer(handleMediumTF, 0, 0, barsToCopy, emaMedium) <= 0) return;
   if(CopyBuffer(handleSlowTF, 0, 0, barsToCopy, emaSlow) <= 0) return;
   if(CopyHigh(_Symbol, tf, 0, barsToCopy, tfHighs) <= 0) return;
   if(CopyLow(_Symbol, tf, 0, barsToCopy, tfLows) <= 0) return;
   if(CopyTime(_Symbol, tf, 0, barsToCopy, tfTimes) <= 0) return;
   if(CopyOpen(_Symbol, tf, 0, barsToCopy, tfOpens) <= 0) return;
   if(CopyClose(_Symbol, tf, 0, barsToCopy, tfCloses) <= 0) return;

   // Estado EMA del HTF
   string emaState = EmaStateToString(emaFast[0], emaMedium[0], emaSlow[0]);
   g_htfEmaState = emaState;

   // Detectar swings del HTF (2 mas recientes de cada tipo)
   double highs[3], lows[3];
   int highCount = 0, lowCount = 0;
   int lookback = InpSwingLookbackHTF;
   int lookforward = InpSwingLookforwardHTF;
   int start = lookback;
   int end = barsToCopy - lookforward - 1;

   for(int i = start; i <= end && (highCount < 2 || lowCount < 2); i++)
   {
      bool isSH = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfHighs[i] <= tfHighs[i - j])
         {
            isSH = false;
            break;
         }
      }
      if(isSH && lookforward > 0)
      {
         for(int j = 1; j <= lookforward; j++)
         {
            if(tfHighs[i] <= tfHighs[i + j])
            {
               isSH = false;
               break;
            }
         }
      }
      if(isSH && highCount < 2)
      {
         highs[highCount] = tfHighs[i];
         highCount++;
      }

      bool isSL = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfLows[i] >= tfLows[i - j])
         {
            isSL = false;
            break;
         }
      }
      if(isSL && lookforward > 0)
      {
         for(int j = 1; j <= lookforward; j++)
         {
            if(tfLows[i] >= tfLows[i + j])
            {
               isSL = false;
               break;
            }
         }
      }
      if(isSL && lowCount < 2)
      {
         lows[lowCount] = tfLows[i];
         lowCount++;
      }
   }

   // Estructura del HTF
   string structure = "Escaneando...";
   if(highCount >= 2 && lowCount >= 2)
   {
      string hPat = GetPattern(highs[0], highs[1], highs[1] * 0.0001) + "H";
      string lPat = GetPattern(lows[0], lows[1], lows[1] * 0.0001) + "L";
      structure = DetectStructureFromPatterns(hPat, lPat);
   }
   g_htfStructure = structure;

   // Construir texto del label
   string fullLabel;
   if(emaState == "Rango")
      fullLabel = (tfCloses[0] >= tfOpens[0]) ? "RA" : "RB";
   else
      fullLabel = EmaStateToShort(emaState) + " " + structure;

   // Color segun combinacion de EMA + estructura
   color textColor;
   if(emaState == "Alcista" && structure == "Im")
      textColor = clrLime;
   else if(emaState == "Bajista" && structure == "Im")
      textColor = clrRed;
   else if(emaState == "Rango")
      textColor = clrYellow;
   else
      textColor = clrOrange;

   CreateLabelAt(LABEL_HTF, TimeframeToString(tf) + ": " + fullLabel, textColor, 10, 50);
}

//+------------------------------------------------------------------+
//| Verifica condiciones para senal de entrada                        |
//| Requiere: HTF y CTF en misma direccion (ambos alcistas o bajistas)|
//| Entry: cuando el precio rompe el nivel opuesto del ultimo swing   |
//| SL: precio del swing, TP: riesgo * InpTPRatio                     |
//| Debounce: solo alerta una vez por barra                           |
//+------------------------------------------------------------------+
void CheckEntrySignal(string emaState, const double &close[], int rates_total, const datetime &time[])
{
   if(emaState == "Rango")
   {
      CreateEntryLabel("No setup", clrGray);
      return;
   }

   if(g_ctfLastSwingHighPrice <= 0 || g_ctfLastSwingLowPrice <= 0)
   {
      CreateEntryLabel("No setup", clrGray);
      return;
   }

   double ctfCloses[];
   ArraySetAsSeries(ctfCloses, true);
   if(CopyClose(_Symbol, Period(), 0, 3, ctfCloses) <= 0) return;

   string signal = "";
   double entryPrice = 0, sl = 0, tp = 0;

   // Senal BUY: HTF alcista + CTF alcista + precio rompe por encima del high del swing low
   if(emaState == "Alcista" && g_ctfEmaState == "Alcista")
   {
      for(int i = 0; i < 3; i++)
      {
         if(ctfCloses[i] > g_ctfLastSwingLowHigh)
         {
            signal = "B";
            entryPrice = g_ctfLastSwingLowHigh;
            sl = g_ctfLastSwingLowPrice;
            double risk = entryPrice - sl;
            tp = entryPrice + risk * InpTPRatio;
            break;
         }
      }
   }

   // Senal SELL: HTF bajista + CTF bajista + precio rompe por debajo del low del swing high
   if(emaState == "Bajista" && g_ctfEmaState == "Bajista")
   {
      for(int i = 0; i < 3; i++)
      {
         if(ctfCloses[i] < g_ctfLastSwingHighLow)
         {
            signal = "S";
            entryPrice = g_ctfLastSwingHighLow;
            sl = g_ctfLastSwingHighPrice;
            double risk = sl - entryPrice;
            tp = entryPrice - risk * InpTPRatio;
            break;
         }
      }
   }

   if(signal != "")
   {
      string text = signal + "  E:" + DoubleToString(entryPrice, _Digits) +
                    "  SL:" + DoubleToString(sl, _Digits) +
                    "  TP:" + DoubleToString(tp, _Digits);
      color col = (signal == "B") ? clrLime : clrRed;
      CreateEntryLabel(text, col);

      // Debounce: solo alerta si es senal nueva o barra diferente
      datetime currentBarTime = time[0];
      if(signal != g_prevEntrySignal || currentBarTime != g_lastSignalBarTime)
      {
         g_prevEntrySignal = signal;
         g_lastSignalBarTime = currentBarTime;

         string msg = "Confluence_v5: " + signal + " setup en " + _Symbol +
                      " E:" + DoubleToString(entryPrice, _Digits) +
                      " SL:" + DoubleToString(sl, _Digits);
         Alert(msg);
         SendNotification(msg);
         PlaySound("alert2.wav");
      }
   }
   else
   {
      g_prevEntrySignal = "";
      CreateEntryLabel("No setup", clrGray);
   }
}

//+------------------------------------------------------------------+
//| Crea label de senal de entrada                                    |
//+------------------------------------------------------------------+
void CreateEntryLabel(string text, color col)
{
   CreateLabelAt(LABEL_ENTRY, text, col, 10, 75);
}
//+------------------------------------------------------------------+
