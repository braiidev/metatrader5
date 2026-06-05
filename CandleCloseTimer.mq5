//+------------------------------------------------------------------+
//|                                              CandleCloseTimer.mq5 |
//|                   Multi-Timeframe countdown to candle close       |
//+------------------------------------------------------------------+
#property copyright "bdev"
#property link      "https://pythonandtrade.bdev.com"
#property version   "2.00"
#property indicator_chart_window
#property indicator_plots 0
#property description "Cuenta regresiva multi-TF al cierre de vela. Clic para alternar entre completo/compacto/oculto."
#property description "Multi-TF countdown to candle close. Click to toggle full/compact/hidden."

input string   TFList       = "current,H1,H4,D1"; // TFs: comma-separated (current=chart TF)
input string   FontFace     = "Arial Bold";
input int      FontSize     = 10;
input color    TextColor    = clrAliceBlue;
input color    UrgentColor  = clrCrimson;
input int      XOffset      = 10;
input int      YOffset      = 30;
input int      LineGap      = 10;

//--- Archivo de persistencia (guarda/restaura estado entre sesiones MT5)
#define SETTINGS_FILE "CandleCloseTimer_settings.txt"

string   g_prefix = "CCT_";
long     g_handle = INVALID_HANDLE;

struct TFEntry
{
   ENUM_TIMEFRAMES tf;
   string          name;
   int             prev_remaining;
   int             state; // 0=full, 1=compact, 2=hidden
};

TFEntry  g_tfs[];
int      g_total = 0;
color    g_bg_color = clrBlack;

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
   return rates_total;
}
//+------------------------------------------------------------------+
int OnInit()
{
   g_handle = ChartID();

   ParseTFList();

   if(g_total == 0)
   {
      Print("CandleCloseTimer: No valid TFs configured.");
      return INIT_FAILED;
   }

   g_bg_color = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);

   for(int i = 0; i < g_total; i++)
   {
      string name = g_prefix + IntegerToString(i);
      ObjectCreate(g_handle, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(g_handle, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(g_handle, name, OBJPROP_XDISTANCE, XOffset);
      ObjectSetInteger(g_handle, name, OBJPROP_YDISTANCE, YOffset + i * (FontSize + LineGap));
      ObjectSetString(g_handle, name, OBJPROP_FONT, FontFace);
      ObjectSetInteger(g_handle, name, OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(g_handle, name, OBJPROP_COLOR, TextColor);
      ObjectSetInteger(g_handle, name, OBJPROP_BACK, false);
      ObjectSetInteger(g_handle, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(g_handle, name, OBJPROP_HIDDEN, true);
   }

   LoadSettings();

   EventSetMillisecondTimer(200u);
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveSettings();
   EventKillTimer();
   for(int i = 0; i < g_total; i++)
      ObjectDelete(g_handle, g_prefix + IntegerToString(i));
}
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, g_prefix) == 0)
   {
      int idx = (int)StringSubstr(sparam, StringLen(g_prefix));
      if(idx >= 0 && idx < g_total)
      {
         g_tfs[idx].state = (g_tfs[idx].state + 1) % 3;
         g_tfs[idx].prev_remaining = -1; // force redraw
         ObjectSetInteger(g_handle, sparam, OBJPROP_STATE, false);
         ChartRedraw(g_handle);
      }
      return;
   }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      g_handle = ChartID();
      g_bg_color = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
      for(int i = 0; i < g_total; i++)
      {
         string name = g_prefix + IntegerToString(i);
         int y = YOffset + i * (FontSize + LineGap);
         ObjectSetInteger(g_handle, name, OBJPROP_XDISTANCE, XOffset);
         ObjectSetInteger(g_handle, name, OBJPROP_YDISTANCE, y);
      }
   }
}
//+------------------------------------------------------------------+
void OnTimer()
{
   datetime cur = TimeCurrent();
   bool changed = false;

   for(int i = 0; i < g_total; i++)
   {
      datetime bar_time = iTime(_Symbol, g_tfs[i].tf, 0);
      if(bar_time == 0) continue;

      int tf_seconds = PeriodSeconds(g_tfs[i].tf);
      int seconds_in = (int)(cur - bar_time);
      int remaining = tf_seconds - seconds_in;
      if(remaining < 0) remaining = 0;

      if(remaining == g_tfs[i].prev_remaining) continue;
      g_tfs[i].prev_remaining = remaining;
      changed = true;

      string name = g_prefix + IntegerToString(i);
      string text;
      color clr;

      if(g_tfs[i].state == 0)
      {
         text = FormatTFLine(g_tfs[i].name, remaining);
         clr = TextColor;
      }
      else if(g_tfs[i].state == 1)
      {
         text = FormatCompact(remaining);
         clr = TextColor;
      }
      else
      {
         text = FormatCompact(remaining);
         clr = g_bg_color;
      }

      if(remaining <= 30 && g_tfs[i].state != 2)
         clr = UrgentColor;

      ObjectSetInteger(g_handle, name, OBJPROP_COLOR, clr);
      ObjectSetString(g_handle, name, OBJPROP_TEXT, text);
   }

   if(changed)
      ChartRedraw(g_handle);
}
//+------------------------------------------------------------------+
string FormatTFLine(string tf_name, int remaining)
{
   int h = remaining / 3600;
   int m = (remaining % 3600) / 60;
   int s = remaining % 60;

   if(h > 0)
      return StringFormat("%s: %02d:%02d:%02d", tf_name, h, m, s);
   else
      return StringFormat("%s: %02d:%02d", tf_name, m, s);
}

string FormatCompact(int remaining)
{
   int h = remaining / 3600;
   int m = (remaining % 3600) / 60;
   int s = remaining % 60;

   if(h > 0)
      return StringFormat("%02d:%02d:%02d", h, m, s);
   else
      return StringFormat("%02d:%02d", m, s);
}
//+------------------------------------------------------------------+
//| Guarda estado (full/compact/hidden) de cada TF                   |
//+------------------------------------------------------------------+
void SaveSettings()
{
   int handle = FileOpen(SETTINGS_FILE, FILE_TXT|FILE_CSV|FILE_WRITE, ",");
   if(handle == INVALID_HANDLE) return;

   for(int i = 0; i < g_total; i++)
      FileWrite(handle, g_tfs[i].state);

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Restaura estado de cada TF desde archivo                          |
//+------------------------------------------------------------------+
void LoadSettings()
{
   int handle = FileOpen(SETTINGS_FILE, FILE_TXT|FILE_CSV|FILE_READ, ",");
   if(handle == INVALID_HANDLE) return;

   for(int i = 0; i < g_total; i++)
   {
      if(FileIsEnding(handle)) break;
      int st = (int)FileReadNumber(handle);
      if(st >= 0 && st <= 2)
      {
         g_tfs[i].state = st;
         g_tfs[i].prev_remaining = -1; // fuerza redibujo
      }
   }

   FileClose(handle);
}

//+------------------------------------------------------------------+
void ParseTFList()
{
   string list = TFList;
   StringReplace(list, " ", "");

   string parts[];
   int count = StringSplit(list, ',', parts);

   if(count <= 0) return;

   ArrayResize(g_tfs, count);
   int added = 0;

   for(int i = 0; i < count; i++)
   {
      string p = parts[i];
      if(p == "") continue;

      ENUM_TIMEFRAMES tf;
      if(p == "current")
         tf = _Period;
      else
         tf = StringToTF(p);

      if(tf == WRONG_VALUE || tf == -1)
      {
         Print("CandleCloseTimer: Unknown TF '", p, "'");
         continue;
      }

      g_tfs[added].tf = tf;
      g_tfs[added].name = TFToString(tf);
      g_tfs[added].prev_remaining = -1;
      g_tfs[added].state = 0;
      added++;
   }

   g_total = added;
   ArrayResize(g_tfs, g_total);
}
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringToTF(string s)
{
   if(s == "M1")  return PERIOD_M1;
   if(s == "M2")  return PERIOD_M2;
   if(s == "M3")  return PERIOD_M3;
   if(s == "M4")  return PERIOD_M4;
   if(s == "M5")  return PERIOD_M5;
   if(s == "M6")  return PERIOD_M6;
   if(s == "M10") return PERIOD_M10;
   if(s == "M12") return PERIOD_M12;
   if(s == "M15") return PERIOD_M15;
   if(s == "M20") return PERIOD_M20;
   if(s == "M30") return PERIOD_M30;
   if(s == "H1")  return PERIOD_H1;
   if(s == "H2")  return PERIOD_H2;
   if(s == "H3")  return PERIOD_H3;
   if(s == "H4")  return PERIOD_H4;
   if(s == "H6")  return PERIOD_H6;
   if(s == "H8")  return PERIOD_H8;
   if(s == "H12") return PERIOD_H12;
   if(s == "D1")  return PERIOD_D1;
   if(s == "W1")  return PERIOD_W1;
   if(s == "MN")  return PERIOD_MN1;
   return WRONG_VALUE;
}
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
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
   }
   return "";
}
//+------------------------------------------------------------------+
