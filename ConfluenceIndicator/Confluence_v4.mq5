//+------------------------------------------------------------------+
//|                                              Confluence_v1.mq5   |
//+------------------------------------------------------------------+
#property copyright ""
#property link      ""
#property version   "4.00"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

#property indicator_label1  "EMA 9"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrOrange
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "EMA 21"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "EMA 50"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

input int InpEmaFast   = 9;
input int InpEmaMedium = 21;
input int InpEmaSlow   = 50;
input ENUM_TIMEFRAMES InpAnalysisTF = PERIOD_H1;
input int InpSwingLookbackH1 = 5;
input int InpSwingLookbackCTF = 5;
input int InpMaxSwingLinesH1 = 6;
input int InpMaxSwingLinesCTF = 6;
input bool InpEntrySignals = true;
input double InpTPRatio = 2.0;

double BufferFast[];
double BufferMedium[];
double BufferSlow[];

int handleFast;
int handleMedium;
int handleSlow;

string labelName = "ConfluenceLabel";
string labelNameTF = "ConfluenceLabelTF";
string labelNameEntry = "ConfluenceLabelEntry";

int handleFastTF;
int handleMediumTF;
int handleSlowTF;

string FormatDateTime(datetime dt)
{
   MqlDateTime dtStruct;
   TimeToStruct(dt, dtStruct);
   string result = StringFormat("%02d/%02d/%02d-%02d:%02d",
      dtStruct.day, dtStruct.mon, dtStruct.year % 100,
      dtStruct.hour, dtStruct.min);
   return result;
}

string GetConfluence(double price)
{
   string conf = "";
   double point = _Point;
   double pip = point * 10;

   if(MathAbs(price - MathRound(price / (pip * 100)) * (pip * 100)) < pip * 5)
      conf += "RN";

   if(MathAbs(price - MathRound(price / (pip * 50)) * (pip * 50)) < pip * 5)
   {
      if(conf != "") conf += "+";
      conf += "R50";
   }

   double prevDayHigh[];
   double prevDayLow[];
   if(CopyHigh(_Symbol, PERIOD_D1, 1, 1, prevDayHigh) > 0)
   {
      if(MathAbs(price - prevDayHigh[0]) < pip * 10)
      {
         if(conf != "") conf += "+";
         conf += "PDH";
      }
   }
   if(CopyLow(_Symbol, PERIOD_D1, 1, 1, prevDayLow) > 0)
   {
      if(MathAbs(price - prevDayLow[0]) < pip * 10)
      {
         if(conf != "") conf += "+";
         conf += "PDL";
      }
   }

   if(conf == "")
      conf = "-";

   return conf;
}

struct SwingPoint
{
   datetime time;
   double price;
   bool isHigh;
};

struct DrawSwing
{
   datetime time;
   double price;
   double linePrice;
   bool isHigh;
   string tfPrefix;
};

SwingPoint lastHighs[3];
SwingPoint lastLows[3];
int highCount = 0;
int lowCount = 0;

double lastSwingHighLinePrice = 0;
datetime lastSwingHighTime = 0;
double lastSwingLowLinePrice = 0;
datetime lastSwingLowTime = 0;
double lastSwingHighPrice = 0;
double lastSwingLowPrice = 0;

double ctfLastSwingHighPrice = 0;
double ctfLastSwingLowPrice = 0;
double ctfLastSwingHighLow = 0;
double ctfLastSwingLowHigh = 0;
string ctfEmaState = "Rango";
string ctfStructure = "Escaneando...";

string prevEntrySignal = "";

int OnInit()
{
   SetIndexBuffer(0, BufferFast, INDICATOR_DATA);
   SetIndexBuffer(1, BufferMedium, INDICATOR_DATA);
   SetIndexBuffer(2, BufferSlow, INDICATOR_DATA);

   handleFast   = iMA(_Symbol, PERIOD_CURRENT, InpEmaFast,   0, MODE_EMA, PRICE_CLOSE);
   handleMedium = iMA(_Symbol, PERIOD_CURRENT, InpEmaMedium, 0, MODE_EMA, PRICE_CLOSE);
   handleSlow   = iMA(_Symbol, PERIOD_CURRENT, InpEmaSlow,   0, MODE_EMA, PRICE_CLOSE);

   if(handleFast == INVALID_HANDLE || handleMedium == INVALID_HANDLE || handleSlow == INVALID_HANDLE)
   {
      Print("Error creating EMA handles");
      return(INIT_FAILED);
   }

   handleFastTF   = iMA(_Symbol, InpAnalysisTF, InpEmaFast,   0, MODE_EMA, PRICE_CLOSE);
   handleMediumTF = iMA(_Symbol, InpAnalysisTF, InpEmaMedium, 0, MODE_EMA, PRICE_CLOSE);
   handleSlowTF   = iMA(_Symbol, InpAnalysisTF, InpEmaSlow,   0, MODE_EMA, PRICE_CLOSE);

   if(handleFastTF == INVALID_HANDLE || handleMediumTF == INVALID_HANDLE || handleSlowTF == INVALID_HANDLE)
   {
      Print("Error creating EMA handles for analysis TF");
      return(INIT_FAILED);
   }

   IndicatorSetString(INDICATOR_SHORTNAME, "Confluence_v1");

   ArraySetAsSeries(BufferFast, true);
   ArraySetAsSeries(BufferMedium, true);
   ArraySetAsSeries(BufferSlow, true);

   return(INIT_SUCCEEDED);
}

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
   if(rates_total < InpSwingLookbackH1 * 4 + 1)
      return(0);

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);

   int toCopy = rates_total - prev_calculated;
   if(toCopy < 0) toCopy = 0;

   if(CopyBuffer(handleFast,   0, 0, rates_total, BufferFast)   <= 0) return(0);
   if(CopyBuffer(handleMedium, 0, 0, rates_total, BufferMedium) <= 0) return(0);
   if(CopyBuffer(handleSlow,   0, 0, rates_total, BufferSlow)   <= 0) return(0);

   int last = 0;
   double emaFast   = BufferFast[last];
   double emaMedium = BufferMedium[last];
   double emaSlow   = BufferSlow[last];

   string emaState = "Rango";

   if(emaFast > emaMedium && emaMedium > emaSlow)
      emaState = "Alcista";
   else if(emaFast < emaMedium && emaMedium < emaSlow)
      emaState = "Bajista";

   DetectSwings(high, low, time, rates_total);

   DrawSwingDotsAndLines(time, high, low, rates_total, emaState);

   string emaShort = "R";
   if(emaState == "Alcista")
      emaShort = "A";
   else if(emaState == "Bajista")
      emaShort = "B";

   string structure = DetectMarketStructure();

   string fullLabel = "";
   if(emaState == "Rango")
   {
      string dir = "RA";
      if(close[0] < open[0])
         dir = "RB";
      fullLabel = dir;
   }
   else
   {
      fullLabel = emaShort + " " + structure;
   }

   CreateLabel(fullLabel, emaState);

    BuildAnalysisTFLabel();

    CheckEntrySignal(emaState, close, high, low, open, rates_total);

    return(rates_total);
}

void DetectSwings(const double &high[], const double &low[], const datetime &time[], int rates_total)
{
   int lookback = InpSwingLookbackH1;
   int start = lookback;
   int end = rates_total - lookback - 1;

   SwingPoint tempHighs[3];
   SwingPoint tempLows[3];
   int highIdx = 0;
   int lowIdx = 0;

   for(int i = start; i <= end && highIdx < 3; i++)
   {
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(high[i] <= high[i - j] || high[i] <= high[i + j])
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         tempHighs[highIdx].time = time[i];
         tempHighs[highIdx].price = high[i];
         tempHighs[highIdx].isHigh = true;
         highIdx++;
      }
   }

   for(int i = start; i <= end && lowIdx < 3; i++)
   {
      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(low[i] >= low[i - j] || low[i] >= low[i + j])
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow)
      {
         tempLows[lowIdx].time = time[i];
         tempLows[lowIdx].price = low[i];
         tempLows[lowIdx].isHigh = false;
         lowIdx++;
      }
   }

   if(highIdx >= 2)
   {
      lastHighs[0] = tempHighs[0];
      lastHighs[1] = tempHighs[1];
      highCount = 2;
   }

   if(lowIdx >= 2)
   {
      lastLows[0] = tempLows[0];
      lastLows[1] = tempLows[1];
      lowCount = 2;
   }
}

string DetectMarketStructure()
{
   string highPattern = "";
   string lowPattern = "";

   if(highCount >= 2)
   {
      double diff = lastHighs[0].price - lastHighs[1].price;
      double threshold = lastHighs[1].price * 0.0001;

      if(diff > threshold)
         highPattern = "HH";
      else if(diff < -threshold)
         highPattern = "LH";
      else
         highPattern = "EH";
   }

   if(lowCount >= 2)
   {
      double diff = lastLows[0].price - lastLows[1].price;
      double threshold = lastLows[1].price * 0.0001;

      if(diff > threshold)
         lowPattern = "HL";
      else if(diff < -threshold)
         lowPattern = "LL";
      else
         lowPattern = "EL";
   }

   if(highPattern == "" || lowPattern == "")
      return "Escaneando...";

   if(highPattern == "HH" && lowPattern == "HL")
      return "Im";
   if(highPattern == "LL" && lowPattern == "LH")
      return "Im";
   if(highPattern == "LH" && lowPattern == "HL")
      return "Pb";
   if(highPattern == "HH" && lowPattern == "LL")
      return "Pb";
   if(highPattern == "EH" || lowPattern == "EL")
      return "Pb";

   return "Pb";
}

void CreateLabel(string text, string emaState)
{
   if(ObjectFind(0, labelName) < 0)
   {
      ObjectCreate(0, labelName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, 25);
      ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, labelName, OBJPROP_FONT, "Arial Bold");
   }

   color textColor;

   if(StringFind(text, "Im") >= 0)
      textColor = clrLime;
   else if(StringFind(text, "Pb") >= 0)
      textColor = clrOrange;
   else
      textColor = clrGray;

   ObjectSetString(0, labelName, OBJPROP_TEXT, "CTF: " + text);
   ObjectSetInteger(0, labelName, OBJPROP_COLOR, textColor);
}

void DrawSwingDotsAndLines(const datetime &time[], const double &high[], const double &low[], int rates_total, string emaState)
{
   DeleteSwingObjects();

   DrawSwingsForTF(PERIOD_H1, false, emaState);

   ENUM_TIMEFRAMES currentTF = Period();
   if(PeriodSeconds(currentTF) < 3600)
      DrawSwingsForTF(currentTF, true, emaState);
}

void DrawSwingsForTF(ENUM_TIMEFRAMES tf, bool isCTF, string emaState)
{
   if(!isCTF)
   {
      lastSwingHighLinePrice = 0;
      lastSwingHighTime = 0;
      lastSwingLowLinePrice = 0;
      lastSwingLowTime = 0;
   }

   int totalBars = iBars(_Symbol, tf);
   int barsToScan = 120;
   if(totalBars < barsToScan)
      barsToScan = totalBars;

   double tfHighs[];
   double tfLows[];
   datetime tfTimes[];

   ArraySetAsSeries(tfHighs, true);
   ArraySetAsSeries(tfLows, true);
   ArraySetAsSeries(tfTimes, true);

   if(CopyHigh(_Symbol, tf, 0, barsToScan, tfHighs) <= 0)
      return;
   if(CopyLow(_Symbol, tf, 0, barsToScan, tfLows) <= 0)
      return;
   if(CopyTime(_Symbol, tf, 0, barsToScan, tfTimes) <= 0)
      return;

    int lookback = isCTF ? InpSwingLookbackCTF : InpSwingLookbackH1;
    int start = lookback;
    int end = barsToScan - lookback - 1;

   DrawSwing allSwings[];
   int swingCount = 0;
   int maxSwings = 100;
   ArrayResize(allSwings, maxSwings);

   string tfPrefix = isCTF ? "CTF" : "H1";

   for(int i = start; i <= end && swingCount < maxSwings; i++)
   {
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfHighs[i] <= tfHighs[i - j] || tfHighs[i] <= tfHighs[i + j])
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         allSwings[swingCount].time = tfTimes[i];
         allSwings[swingCount].price = tfHighs[i];
         allSwings[swingCount].linePrice = tfLows[i];
         allSwings[swingCount].isHigh = true;
         allSwings[swingCount].tfPrefix = tfPrefix;
         swingCount++;
      }

      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfLows[i] >= tfLows[i - j] || tfLows[i] >= tfLows[i + j])
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow)
      {
         allSwings[swingCount].time = tfTimes[i];
         allSwings[swingCount].price = tfLows[i];
         allSwings[swingCount].linePrice = tfHighs[i];
         allSwings[swingCount].isHigh = false;
         allSwings[swingCount].tfPrefix = tfPrefix;
         swingCount++;
      }
   }

   ArrayResize(allSwings, swingCount);
   SortSwingsByTime(allSwings, swingCount);

   DrawSwing filtered[];
   int filteredCount = 0;
   ArrayResize(filtered, swingCount);

   if(swingCount > 0)
   {
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
   }

   if(isCTF && filteredCount >= 2)
   {
      ctfEmaState = emaState;
      double lastHigh = 0;
      double lastLow = 999999999;
      double lastHighLow = 0;
      double lastLowHigh = 0;
      bool gotHigh = false;
      bool gotLow = false;

      for(int i = 0; i < filteredCount; i++)
      {
         if(filtered[i].isHigh && !gotHigh)
         {
            lastHigh = filtered[i].price;
            lastHighLow = filtered[i].linePrice;
            gotHigh = true;
         }
         else if(!filtered[i].isHigh && !gotLow)
         {
            lastLow = filtered[i].price;
            lastLowHigh = filtered[i].linePrice;
            gotLow = true;
         }
      }

      ctfLastSwingHighPrice = lastHigh;
      ctfLastSwingLowPrice = lastLow;
      ctfLastSwingHighLow = lastHighLow;
      ctfLastSwingLowHigh = lastLowHigh;

      string highPattern = "";
      string lowPattern = "";
      double prevHigh = 0;
      double prevLow = 999999999;

      for(int i = 0; i < filteredCount; i++)
      {
         if(filtered[i].isHigh)
         {
            if(prevHigh == 0) prevHigh = filtered[i].price;
            else { prevHigh = filtered[i].price; break; }
         }
         else
         {
            if(prevLow == 999999999) prevLow = filtered[i].price;
         }
      }

      if(gotHigh && prevHigh > 0 && prevHigh != lastHigh)
      {
         double diff = lastHigh - prevHigh;
         double threshold = prevHigh * 0.0001;
         if(diff > threshold) highPattern = "HH";
         else if(diff < -threshold) highPattern = "LH";
         else highPattern = "EH";
      }

      if(gotLow && prevLow < 999999999 && prevLow != lastLow)
      {
         double diff = lastLow - prevLow;
         double threshold = prevLow * 0.0001;
         if(diff > threshold) lowPattern = "HL";
         else if(diff < -threshold) lowPattern = "LL";
         else lowPattern = "EL";
      }

       if(highPattern != "" && lowPattern != "")
          ctfStructure = highPattern + "-" + lowPattern;
       else
          ctfStructure = "Escaneando...";
    }

    if(!isCTF && filteredCount >= 2)
    {
       bool gotHigh = false;
       bool gotLow = false;
       for(int i = 0; i < filteredCount && (!gotHigh || !gotLow); i++)
       {
          if(filtered[i].isHigh && !gotHigh)
          {
             lastSwingHighLinePrice = filtered[i].linePrice;
             lastSwingHighTime = filtered[i].time;
             lastSwingHighPrice = filtered[i].price;
             gotHigh = true;
          }
          else if(!filtered[i].isHigh && !gotLow)
          {
             lastSwingLowLinePrice = filtered[i].linePrice;
             lastSwingLowTime = filtered[i].time;
             lastSwingLowPrice = filtered[i].price;
             gotLow = true;
          }
       }
    }

   int maxLines = isCTF ? InpMaxSwingLinesCTF : InpMaxSwingLinesH1;
   int drawn = 0;
   for(int i = 0; i < filteredCount && drawn < maxLines; i++)
   {
      datetime dt = filtered[i].time;
      string dtStr = FormatDateTime(dt);
      string prefix = filtered[i].tfPrefix;

      color dotColor, lineColor;
      int dotWidth;

      dotColor = filtered[i].isHigh ? (isCTF ? C'144,238,144' : clrLime) : (isCTF ? C'255,182,193' : clrRed);
      dotWidth = isCTF ? 2 : 3;

      bool isAFT = (emaState == "Bajista" && filtered[i].isHigh) || (emaState == "Alcista" && !filtered[i].isHigh);

      if(isAFT)
         lineColor = filtered[i].isHigh ? (isCTF ? C'144,238,144' : clrLime) : (isCTF ? C'255,182,193' : clrRed);
      else
         lineColor = C'105,105,105';

      if(filtered[i].isHigh)
      {
         string conf = GetConfluence(filtered[i].linePrice);
         string objName = "SwingDot_H_" + prefix + "_" + dtStr + "_" + IntegerToString(i);
         ObjectCreate(0, objName, OBJ_ARROW, 0, dt, filtered[i].price);
         ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 159);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, dotColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, dotWidth);
         ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
         ObjectSetString(0, objName, OBJPROP_TEXT, "SwingH " + prefix + " " + dtStr + " " + conf);

         string lineName = "SwingLine_L_" + prefix + "_" + dtStr + "_" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_TREND, 0, dt, filtered[i].linePrice, TimeCurrent(), filtered[i].linePrice);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, isCTF ? 1 : 1);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetString(0, lineName, OBJPROP_TEXT, "SwingL " + prefix + " " + dtStr + " " + conf);
      }
      else
      {
         string conf = GetConfluence(filtered[i].linePrice);
         string objName = "SwingDot_L_" + prefix + "_" + dtStr + "_" + IntegerToString(i);
         ObjectCreate(0, objName, OBJ_ARROW, 0, dt, filtered[i].price);
         ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, 159);
         ObjectSetInteger(0, objName, OBJPROP_COLOR, dotColor);
         ObjectSetInteger(0, objName, OBJPROP_WIDTH, dotWidth);
         ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_TOP);
         ObjectSetString(0, objName, OBJPROP_TEXT, "SwingL " + prefix + " " + dtStr + " " + conf);

         string lineName = "SwingLine_H_" + prefix + "_" + dtStr + "_" + IntegerToString(i);
         ObjectCreate(0, lineName, OBJ_TREND, 0, dt, filtered[i].linePrice, TimeCurrent(), filtered[i].linePrice);
         ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
         ObjectSetInteger(0, lineName, OBJPROP_WIDTH, isCTF ? 1 : 1);
         ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
         ObjectSetString(0, lineName, OBJPROP_TEXT, "SwingH " + prefix + " " + dtStr + " " + conf);
      }
      drawn++;
   }
}

void SortSwingsByTime(DrawSwing &swings[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(swings[j].time > swings[i].time)
         {
            DrawSwing temp = swings[i];
            swings[i] = swings[j];
            swings[j] = temp;
         }
      }
   }
}


void DeleteSwingObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "SwingDot_") == 0 || StringFind(name, "SwingLine_") == 0)
         ObjectDelete(0, name);
   }
}

void CheckEntrySignal(string h1EmaState, const double &close[], const double &high[], const double &low[], const double &open[], int rates_total)
{
   if(!InpEntrySignals)
   {
      CreateEntryLabel("No setup", clrGray);
      return;
   }

   if(h1EmaState == "Rango")
   {
      CreateEntryLabel("No setup", clrGray);
      return;
   }

   ENUM_TIMEFRAMES ctf = Period();
   if(PeriodSeconds(ctf) >= 3600)
   {
      CreateEntryLabel("No setup", clrGray);
      return;
   }

   if(ctfLastSwingHighPrice <= 0 || ctfLastSwingLowPrice <= 0)
   {
      CreateEntryLabel("No setup", clrGray);
      return;
   }

   double ctfCloses[];
   ArraySetAsSeries(ctfCloses, true);
   if(CopyClose(_Symbol, ctf, 0, 3, ctfCloses) <= 0) return;

   string signal = "";
   double entryPrice = 0;
   double sl = 0;
   double tp = 0;

   if(h1EmaState == "Alcista" && ctfEmaState == "Alcista")
   {
      for(int i = 0; i < 3; i++)
      {
         if(ctfCloses[i] > ctfLastSwingLowHigh)
         {
            signal = "B";
            entryPrice = ctfLastSwingLowHigh;
            sl = ctfLastSwingLowPrice;
            double risk = entryPrice - sl;
            tp = entryPrice + risk * InpTPRatio;
            break;
         }
      }
   }

   if(h1EmaState == "Bajista" && ctfEmaState == "Bajista")
   {
      for(int i = 0; i < 3; i++)
      {
         if(ctfCloses[i] < ctfLastSwingHighLow)
         {
            signal = "S";
            entryPrice = ctfLastSwingHighLow;
            sl = ctfLastSwingHighPrice;
            double risk = sl - entryPrice;
            tp = entryPrice - risk * InpTPRatio;
            break;
         }
      }
   }

   if(signal != "")
   {
      string text = signal + "  E:" + DoubleToString(entryPrice, _Digits) + "  SL:" + DoubleToString(sl, _Digits) + "  TP:" + DoubleToString(tp, _Digits);
      color col = (signal == "B") ? clrLime : clrRed;
      CreateEntryLabel(text, col);

      if(signal != prevEntrySignal)
      {
         prevEntrySignal = signal;
         string msg = "Confluence_v1: " + signal + " setup en " + _Symbol + " E:" + DoubleToString(entryPrice, _Digits) + " SL:" + DoubleToString(sl, _Digits);
         Alert(msg);
         SendNotification(msg);
         PlaySound("alert2.wav");
      }
   }
   else
   {
      prevEntrySignal = "";
      CreateEntryLabel("No setup", clrGray);
   }
}

void CreateEntryLabel(string text, color col)
{
   if(ObjectFind(0, labelNameEntry) < 0)
   {
      ObjectCreate(0, labelNameEntry, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelNameEntry, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, labelNameEntry, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, labelNameEntry, OBJPROP_YDISTANCE, 75);
      ObjectSetInteger(0, labelNameEntry, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, labelNameEntry, OBJPROP_FONT, "Arial Bold");
   }

   ObjectSetString(0, labelNameEntry, OBJPROP_TEXT, text);
   ObjectSetInteger(0, labelNameEntry, OBJPROP_COLOR, col);
}

void OnDeinit(const int reason)
{
   if(handleFast   != INVALID_HANDLE) IndicatorRelease(handleFast);
   if(handleMedium != INVALID_HANDLE) IndicatorRelease(handleMedium);
   if(handleSlow   != INVALID_HANDLE) IndicatorRelease(handleSlow);
   if(handleFastTF   != INVALID_HANDLE) IndicatorRelease(handleFastTF);
   if(handleMediumTF != INVALID_HANDLE) IndicatorRelease(handleMediumTF);
   if(handleSlowTF   != INVALID_HANDLE) IndicatorRelease(handleSlowTF);

   ObjectDelete(0, labelName);
   ObjectDelete(0, labelNameTF);
   DeleteSwingObjects();
}

void BuildAnalysisTFLabel()
{
   ENUM_TIMEFRAMES tf = InpAnalysisTF;
   int tfBars = iBars(_Symbol, tf);
   if(tfBars < InpSwingLookbackH1 * 4 + 1)
      return;

   double emaFast[];
   double emaMedium[];
   double emaSlow[];
   datetime tfTimes[];
   double tfHighs[];
   double tfLows[];
   double tfOpens[];
   double tfCloses[];

   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaMedium, true);
   ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(tfTimes, true);
   ArraySetAsSeries(tfHighs, true);
   ArraySetAsSeries(tfLows, true);
   ArraySetAsSeries(tfOpens, true);
   ArraySetAsSeries(tfCloses, true);

   if(CopyBuffer(handleFastTF, 0, 0, tfBars, emaFast) <= 0) return;
   if(CopyBuffer(handleMediumTF, 0, 0, tfBars, emaMedium) <= 0) return;
   if(CopyBuffer(handleSlowTF, 0, 0, tfBars, emaSlow) <= 0) return;
   if(CopyHigh(_Symbol, tf, 0, tfBars, tfHighs) <= 0) return;
   if(CopyLow(_Symbol, tf, 0, tfBars, tfLows) <= 0) return;
   if(CopyTime(_Symbol, tf, 0, tfBars, tfTimes) <= 0) return;
   if(CopyOpen(_Symbol, tf, 0, tfBars, tfOpens) <= 0) return;
   if(CopyClose(_Symbol, tf, 0, tfBars, tfCloses) <= 0) return;

   string emaState = "Rango";
   if(emaFast[0] > emaMedium[0] && emaMedium[0] > emaSlow[0])
      emaState = "Alcista";
   else if(emaFast[0] < emaMedium[0] && emaMedium[0] < emaSlow[0])
      emaState = "Bajista";

   int lookback = InpSwingLookbackH1;
   int start = lookback;
   int end = tfBars - lookback - 1;

   SwingPoint tempHighs[3];
   SwingPoint tempLows[3];
   int highIdx = 0;
   int lowIdx = 0;

   for(int i = start; i <= end && highIdx < 3; i++)
   {
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfHighs[i] <= tfHighs[i - j] || tfHighs[i] <= tfHighs[i + j])
         {
            isSwingHigh = false;
            break;
         }
      }
      if(isSwingHigh)
      {
         tempHighs[highIdx].time = tfTimes[i];
         tempHighs[highIdx].price = tfHighs[i];
         tempHighs[highIdx].isHigh = true;
         highIdx++;
      }
   }

   for(int i = start; i <= end && lowIdx < 3; i++)
   {
      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(tfLows[i] >= tfLows[i - j] || tfLows[i] >= tfLows[i + j])
         {
            isSwingLow = false;
            break;
         }
      }
      if(isSwingLow)
      {
         tempLows[lowIdx].time = tfTimes[i];
         tempLows[lowIdx].price = tfLows[i];
         tempLows[lowIdx].isHigh = false;
         lowIdx++;
      }
   }

   string structure = "Escaneando...";
   if(highIdx >= 2 && lowIdx >= 2)
   {
      string highPattern = "";
      string lowPattern = "";

      double hDiff = tempHighs[0].price - tempHighs[1].price;
      double hThresh = tempHighs[1].price * 0.0001;
      if(hDiff > hThresh) highPattern = "HH";
      else if(hDiff < -hThresh) highPattern = "LH";
      else highPattern = "EH";

      double lDiff = tempLows[0].price - tempLows[1].price;
      double lThresh = tempLows[1].price * 0.0001;
      if(lDiff > lThresh) lowPattern = "HL";
      else if(lDiff < -lThresh) lowPattern = "LL";
      else lowPattern = "EL";

      if(highPattern == "HH" && lowPattern == "HL")
         structure = "Im";
      else if(highPattern == "LL" && lowPattern == "LH")
         structure = "Im";
      else if(highPattern == "LH" && lowPattern == "HL")
         structure = "Pb";
      else if(highPattern == "HH" && lowPattern == "LL")
         structure = "Pb";
      else if(highPattern == "EH" || lowPattern == "EL")
         structure = "Pb";
      else
         structure = "Pb";
   }

   string emaShort = "R";
   if(emaState == "Alcista")
      emaShort = "A";
   else if(emaState == "Bajista")
      emaShort = "B";

   string fullLabel = "";
   if(emaState == "Rango")
   {
      string dir = "RA";
      if(tfCloses[0] < tfOpens[0])
         dir = "RB";
      fullLabel = dir;
   }
   else
   {
      fullLabel = emaShort + " " + structure;
   }

   if(ObjectFind(0, labelNameTF) < 0)
   {
      ObjectCreate(0, labelNameTF, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, labelNameTF, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, labelNameTF, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, labelNameTF, OBJPROP_YDISTANCE, 50);
      ObjectSetInteger(0, labelNameTF, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, labelNameTF, OBJPROP_FONT, "Arial Bold");
   }

   color textColor;
   if(emaState == "Alcista" && structure == "Im")
      textColor = clrLime;
   else if(emaState == "Bajista" && structure == "Im")
      textColor = clrRed;
   else if(emaState == "Rango")
      textColor = clrYellow;
   else
      textColor = clrOrange;

   string tfStr = "";
   if(InpAnalysisTF == PERIOD_H1) tfStr = "H1";
   else if(InpAnalysisTF == PERIOD_H2) tfStr = "H2";
   else if(InpAnalysisTF == PERIOD_H3) tfStr = "H3";
   else if(InpAnalysisTF == PERIOD_H4) tfStr = "H4";
   else if(InpAnalysisTF == PERIOD_H6) tfStr = "H6";
   else if(InpAnalysisTF == PERIOD_H8) tfStr = "H8";
   else if(InpAnalysisTF == PERIOD_H12) tfStr = "H12";
   else if(InpAnalysisTF == PERIOD_D1) tfStr = "D1";
   else tfStr = "H1";

   ObjectSetString(0, labelNameTF, OBJPROP_TEXT, tfStr + ": " + fullLabel);
   ObjectSetInteger(0, labelNameTF, OBJPROP_COLOR, textColor);
}
//+------------------------------------------------------------------+
