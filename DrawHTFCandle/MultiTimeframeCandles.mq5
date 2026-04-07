//+------------------------------------------------------------------+
//|                                         MultiTimeframeCandles.mq5 |
//|                                  Multi-Timeframe OHLC Background  |
//+------------------------------------------------------------------+
#property copyright "Multi-Timeframe Candles"
#property link      ""
#property version   "4.0"
#property indicator_chart_window
#property indicator_plots 0

input group "=== Configuracion ==="
input color   BullColor       = C'46,125,50';
input color   BearColor       = C'183,28,28';
input bool    ShowWicks       = true;
input int     WickWidth       = 2;
input int     MaxCandles      = 200;

input group "=== Panel ==="
input int     PanelX          = 0;
input int     PanelY          = 50;

ENUM_TIMEFRAMES Timeframes[] = {
   PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M4, PERIOD_M5, PERIOD_M6,
   PERIOD_M10, PERIOD_M12, PERIOD_M15, PERIOD_M20, PERIOD_M30,
   PERIOD_H1, PERIOD_H2, PERIOD_H3, PERIOD_H4, PERIOD_H6, PERIOD_H8, PERIOD_H12,
   PERIOD_D1, PERIOD_W1, PERIOD_MN1
};

string TFNames[] = {
   "M1", "M2", "M3", "M4", "M5", "M6",
   "M10", "M12", "M15", "M20", "M30",
   "H1", "H2", "H3", "H4", "H6", "H8", "H12",
   "D1", "W1", "MN"
};

const string PREFIX = "MTCandles_";
const string PREFIX_BTN = "MTCandles_btn_";
const string PREFIX_CANDLE = "MTCandles_candle_";
const string PREFIX_WICK = "MTCandles_wick_";
const int PREFIX_BTN_LEN = 14;

ENUM_TIMEFRAMES g_selected_tf = WRONG_VALUE;
int g_selected_tf_index = -1;
int g_total_candles = 0;
datetime g_last_htf_bar_time = 0;
string g_candle_names[];
string g_wick_names[];

int g_button_width = 50;
int g_button_height = 22;
int g_button_gap = 2;
bool g_panel_visible = false;

int OnInit()
{
   ENUM_TIMEFRAMES current_tf = Period();
   bool has_higher_tf = false;
   int total = ArraySize(Timeframes);
   for(int i = 0; i < total; i++)
   {
      if(Timeframes[i] > current_tf)
      {
         has_higher_tf = true;
         break;
      }
   }
   if(!has_higher_tf)
   {
      Print("MTCandles: No higher timeframe available for ", EnumToString(current_tf));
      return(INIT_FAILED);
   }

   EventSetTimer(1);

   ArrayResize(g_candle_names, MaxCandles);
   ArrayResize(g_wick_names, MaxCandles);

   CreatePanel();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllObjects();
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
   return(rates_total);
}

void OnTimer()
{
   if(g_selected_tf <= Period())
      return;

   MqlRates rates[];
   if(CopyRates(Symbol(), g_selected_tf, 0, 1, rates) < 1)
      return;

   if(rates[0].time != g_last_htf_bar_time)
   {
      if(g_total_candles > 0)
      {
         RedrawAllCandles();
      }
      else
      {
         DrawHigherTF();
      }
      return;
   }

   if(g_total_candles == 0)
      return;

   UpdateFormingCandle(rates[0]);
}

void UpdateFormingCandle(const MqlRates &current_rate)
{
   bool is_bull = current_rate.close >= current_rate.open;
   color candle_color = is_bull ? BullColor : BearColor;
   datetime end_time = current_rate.time + PeriodSeconds(g_selected_tf);

   string candle_name = PREFIX_CANDLE + "0";
   if(ObjectFind(0, candle_name) >= 0)
   {
      ObjectMove(0, candle_name, 0, current_rate.time, current_rate.open);
      ObjectMove(0, candle_name, 1, end_time, current_rate.close);
      ObjectSetInteger(0, candle_name, OBJPROP_COLOR, candle_color);
   }

   if(ShowWicks)
   {
      string wick_name = PREFIX_WICK + "0";
      if(ObjectFind(0, wick_name) >= 0)
      {
         datetime mid_time = current_rate.time + PeriodSeconds(g_selected_tf) / 2;
         ObjectMove(0, wick_name, 0, mid_time, current_rate.low);
         ObjectMove(0, wick_name, 1, mid_time, current_rate.high);
         ObjectSetInteger(0, wick_name, OBJPROP_COLOR, candle_color);
      }
   }
}

void RedrawAllCandles()
{
   ClearCandles(false);

   MqlRates rates[];
   int count = CopyRates(Symbol(), g_selected_tf, 0, MaxCandles, rates);
   if(count <= 0)
      return;

   ArraySetAsSeries(rates, true);

   datetime now = TimeCurrent();
   int drawn = 0;

   for(int i = 0; i < count && drawn < MaxCandles; i++)
   {
      if(rates[i].time > now)
         continue;

      bool is_bull = rates[i].close >= rates[i].open;
      color candle_color = is_bull ? BullColor : BearColor;
      datetime end_time = rates[i].time + PeriodSeconds(g_selected_tf);

      DrawCandleBody(rates[i].time, end_time, rates[i].open, rates[i].close, candle_color, drawn);

      if(ShowWicks)
         DrawWick(rates[i].time, end_time, rates[i].high, rates[i].low, candle_color, drawn);

      drawn++;
   }

   g_total_candles = drawn;
   g_last_htf_bar_time = rates[0].time;
   ChartRedraw();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(g_selected_tf != WRONG_VALUE)
      {
         if(g_selected_tf <= Period())
         {
            Print("MTCandles: Selected TF no longer higher than chart TF. Clearing.");
            g_selected_tf = WRONG_VALUE;
            g_selected_tf_index = -1;
            ClearCandles();
            DeleteUnusedButtons();
         }
         else
         {
            DeleteUnusedButtons();
            if(g_panel_visible)
               CreateTFButtons();
         }
      }
      else
      {
         DeleteUnusedButtons();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == PREFIX + "toggle")
      {
         g_panel_visible = !g_panel_visible;
         UpdatePanelVisibility();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }

      if(StringFind(sparam, PREFIX_BTN) == 0)
      {
         string tf_name = StringSubstr(sparam, PREFIX_BTN_LEN);
         int tf_index = FindTFIndex(tf_name);

         if(tf_index < 0)
            return;

         ENUM_TIMEFRAMES tf = Timeframes[tf_index];

         if(tf <= Period())
         {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            return;
         }

         if(g_selected_tf_index == tf_index)
         {
            g_selected_tf = WRONG_VALUE;
            g_selected_tf_index = -1;
            ClearCandles();
         }
         else
         {
            int old_index = g_selected_tf_index;
            g_selected_tf = tf;
            g_selected_tf_index = tf_index;

            if(old_index >= 0)
            {
               string old_btn = PREFIX_BTN + TFNames[old_index];
               if(ObjectFind(0, old_btn) >= 0)
                  ObjectSetInteger(0, old_btn, OBJPROP_STATE, false);
            }

            ClearCandles();
            DrawHigherTF();
         }
      }
   }
}

void CreatePanel()
{
   string toggle_name = PREFIX + "toggle";
   if(ObjectFind(0, toggle_name) < 0)
   {
      ObjectCreate(0, toggle_name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, toggle_name, OBJPROP_XDISTANCE, GetStartX());
      ObjectSetInteger(0, toggle_name, OBJPROP_YDISTANCE, PanelY);
      ObjectSetInteger(0, toggle_name, OBJPROP_XSIZE, g_button_width);
      ObjectSetInteger(0, toggle_name, OBJPROP_YSIZE, g_button_height);
      ObjectSetInteger(0, toggle_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, toggle_name, OBJPROP_TEXT, "TF");
      ObjectSetInteger(0, toggle_name, OBJPROP_FONTSIZE, 8);
      ObjectSetString(0, toggle_name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, toggle_name, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, toggle_name, OBJPROP_BGCOLOR, clrDarkSlateGray);
      ObjectSetInteger(0, toggle_name, OBJPROP_BORDER_COLOR, clrBlack);
      ObjectSetInteger(0, toggle_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, toggle_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, toggle_name, OBJPROP_HIDDEN, true);
   }

   DeleteUnusedButtons();
   UpdatePanelVisibility();
}

void CreateTFButtons()
{
   int total = ArraySize(Timeframes);
   ENUM_TIMEFRAMES current_tf = Period();
   int start_x = GetStartX();
   int btn_count = 0;

   for(int i = 0; i < total; i++)
   {
      if(Timeframes[i] <= current_tf)
         continue;

      int y = PanelY + g_button_height + g_button_gap + btn_count * (g_button_height + g_button_gap);
      string btn_name = PREFIX_BTN + TFNames[i];

      if(ObjectFind(0, btn_name) < 0)
      {
         ObjectCreate(0, btn_name, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, btn_name, OBJPROP_XDISTANCE, start_x);
         ObjectSetInteger(0, btn_name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, btn_name, OBJPROP_XSIZE, g_button_width);
         ObjectSetInteger(0, btn_name, OBJPROP_YSIZE, g_button_height);
         ObjectSetInteger(0, btn_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetString(0, btn_name, OBJPROP_TEXT, TFNames[i]);
         ObjectSetInteger(0, btn_name, OBJPROP_FONTSIZE, 8);
         ObjectSetString(0, btn_name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, btn_name, OBJPROP_COLOR, clrWhite);
         ObjectSetInteger(0, btn_name, OBJPROP_BGCOLOR, clrDimGray);
         ObjectSetInteger(0, btn_name, OBJPROP_BORDER_COLOR, clrBlack);
         ObjectSetInteger(0, btn_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(0, btn_name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, btn_name, OBJPROP_HIDDEN, true);

         if(g_selected_tf_index == i)
            ObjectSetInteger(0, btn_name, OBJPROP_STATE, true);
      }

      btn_count++;
   }
}

void DeleteTFButtons()
{
   int total = ArraySize(TFNames);
   for(int i = 0; i < total; i++)
   {
      ObjectDelete(0, PREFIX_BTN + TFNames[i]);
   }
}

void UpdatePanelVisibility()
{
   if(g_panel_visible)
      CreateTFButtons();
   else
      DeleteTFButtons();
   ChartRedraw();
}

void DeleteUnusedButtons()
{
   ENUM_TIMEFRAMES current_tf = Period();
   int total = ArraySize(TFNames);

   for(int i = 0; i < total; i++)
   {
      if(Timeframes[i] <= current_tf)
         ObjectDelete(0, PREFIX_BTN + TFNames[i]);
   }
}

int FindTFIndex(string name)
{
   int total = ArraySize(TFNames);
   for(int i = 0; i < total; i++)
   {
      if(TFNames[i] == name)
         return i;
   }
   return -1;
}

void ClearCandles(const bool redraw = true)
{
   for(int i = 0; i < g_total_candles; i++)
   {
      if(g_candle_names[i] != "")
      {
         ObjectDelete(0, g_candle_names[i]);
         g_candle_names[i] = "";
      }
      if(g_wick_names[i] != "")
      {
         ObjectDelete(0, g_wick_names[i]);
         g_wick_names[i] = "";
      }
   }

   g_total_candles = 0;
   g_last_htf_bar_time = 0;

   if(redraw)
      ChartRedraw();
}

void DrawHigherTF()
{
   if(g_selected_tf <= Period())
      return;

   MqlRates rates[];
   int count = CopyRates(Symbol(), g_selected_tf, 0, MaxCandles, rates);
   if(count <= 0)
   {
      Print("MTCandles: CopyRates failed for ", EnumToString(g_selected_tf));
      return;
   }

   ArraySetAsSeries(rates, true);

   datetime now = TimeCurrent();
   int drawn = 0;

   for(int i = 0; i < count && drawn < MaxCandles; i++)
   {
      if(rates[i].time > now)
         continue;

      bool is_bull = rates[i].close >= rates[i].open;
      color candle_color = is_bull ? BullColor : BearColor;
      datetime end_time = rates[i].time + PeriodSeconds(g_selected_tf);

      DrawCandleBody(rates[i].time, end_time, rates[i].open, rates[i].close, candle_color, drawn);

      if(ShowWicks)
         DrawWick(rates[i].time, end_time, rates[i].high, rates[i].low, candle_color, drawn);

      drawn++;
   }

   g_total_candles = drawn;
   g_last_htf_bar_time = rates[0].time;
   ChartRedraw();
}

void DrawCandleBody(datetime start_time, datetime end_time,
                    double open, double close,
                    color candle_color, int index)
{
   if(index >= MaxCandles)
      return;

   string name = PREFIX_CANDLE + IntegerToString(index);

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, start_time, open, end_time, close);
   }
   else
   {
      ObjectMove(0, name, 0, start_time, open);
      ObjectMove(0, name, 1, end_time, close);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, candle_color);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

   g_candle_names[index] = name;
}

void DrawWick(datetime start_time, datetime end_time,
              double high, double low, color wick_color, int index)
{
   if(index >= MaxCandles)
      return;

   string name = PREFIX_WICK + IntegerToString(index);
   datetime mid_time = start_time + (end_time - start_time) / 2;

   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_TREND, 0, mid_time, low, mid_time, high);
   }
   else
   {
      ObjectMove(0, name, 0, mid_time, low);
      ObjectMove(0, name, 1, mid_time, high);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, wick_color);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, WickWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);

   g_wick_names[index] = name;
}

void DeleteAllObjects()
{
   ClearCandles(false);

   int total = ArraySize(TFNames);
   for(int i = 0; i < total; i++)
   {
      ObjectDelete(0, PREFIX_BTN + TFNames[i]);
   }
   ObjectDelete(0, PREFIX + "toggle");

   ChartRedraw();
}

int GetStartX()
{
   if(PanelX != 0)
      return PanelX;

   long chart_width = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   return (int)chart_width - g_button_width - 30;
}
//+------------------------------------------------------------------+
