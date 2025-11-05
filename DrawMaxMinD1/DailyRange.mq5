//+------------------------------------------------------------------+
//|                                                   CRTSession.mq5 |
//+------------------------------------------------------------------+
#property copyright "Braiidev"
#property link      "@braiidev-github-instagram"
#property version   "1.00"
#property indicator_chart_window

//--- input parameters
input int      CR_style       = STYLE_SOLID;
input color    CR_color       = clrSienna;
input bool     CRT_RAY        = false;

//--- estructuras ----------------------------------------------------
struct candleRange
 {
  string             name;
  string             type;
  datetime           dt;
  MqlDateTime        sdt;
  double             highPrice;
  double             lowPrice;
  int                shift;
  string             highName;
  string             lowName;
  color              lineColor;
  int                lineStyle;
  bool               isDraw;
 };

//--- array global de rangos
candleRange candles[3];

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
 {
  DeleteAllObjects("CR");

// cargar 3 rangos (actual, previo, último)
  LoadCrt(candles[0], "CR", "current", 0);
  LoadCrt(candles[1], "CR", "prev", 1);
  LoadCrt(candles[2], "CR", "last", 2);

  return(INIT_SUCCEEDED);
 }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
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
                const int32_t &spread[])
 {
// actualizar precios de rangos
  candleRangeUpdate(candles[0]);
  candleRangeUpdate(candles[1]);
  candleRangeUpdate(candles[2]);

  return(rates_total);
 }

//+------------------------------------------------------------------+
//| Eliminar objetos por prefijo                                    |
//+------------------------------------------------------------------+
void DeleteAllObjects(string prefix)
 {
  int total = ObjectsTotal(0);
  for(int i = total - 1; i >= 0; i--)
   {
    string obj = ObjectName(0, i);
    if(StringFind(obj, prefix, 0) == 0)
      ObjectDelete(0, obj);
   }
 }

//+------------------------------------------------------------------+
//| Actualiza líneas si cambia el rango diario                       |
//+------------------------------------------------------------------+
void candleRangeUpdate(candleRange &o)
 {
  double high = iHigh(_Symbol, PERIOD_D1, o.shift);
  double low  = iLow(_Symbol, PERIOD_D1, o.shift);

  if(o.highPrice != high)
   {
    o.highPrice = high;
    if(ObjectFind(0, o.highName) != -1)
     {
      ObjectMove(0, o.highName, 0, o.dt, o.highPrice);
     }
    else
      return;
   }
  ObjectMove(0, o.highName, 1, TimeCurrent(), o.highPrice);
  if(o.lowPrice != low)
   {
    o.lowPrice = low;
    if(ObjectFind(0, o.lowName) != -1)
     {
      ObjectMove(0, o.lowName, 0, o.dt, o.lowPrice);
     }
    else
      return;
   }
  ObjectMove(0, o.lowName, 1, TimeCurrent(), o.lowPrice);
 }

//+------------------------------------------------------------------+
//| Cargar líneas en gráfico                                         |
//+------------------------------------------------------------------+
void LoadCrt(candleRange &o, string name, string type, int shift = 0)
 {
  o.name       = name;
  o.dt         = iTime(_Symbol, PERIOD_D1, shift);
  TimeToStruct(o.dt, o.sdt);
  o.type       = type;
  o.shift      = shift;
  o.lineColor  = CR_color;
  o.lineStyle  = CR_style;
  o.highPrice  = iHigh(_Symbol, PERIOD_D1, shift);
  o.lowPrice   = iLow(_Symbol, PERIOD_D1, shift);
  o.highName   = name + "H_" + type;
  o.lowName    = name + "L_" + type;
  o.isDraw     = false;

  string result = DrawLines(o);
  Print("CR: ", o.type, " -> ", result);
 }

//+------------------------------------------------------------------+
//| Dibuja líneas de rango                                           |
//+------------------------------------------------------------------+
string DrawLines(candleRange &o)
 {
  bool high = DrawLine(o.highName, o.dt, o.highPrice, o.lineColor, o.lineStyle, o.type + " high");
  bool low  = DrawLine(o.lowName,  o.dt, o.lowPrice,  o.lineColor, o.lineStyle, o.type + " low");

  if(high && low)
   {
    o.isDraw = true;
    return "Load Success";
   }
  return "We have a problem!";
 }

//+------------------------------------------------------------------+
//| Crear/actualizar línea horizontal                                |
//+------------------------------------------------------------------+
bool DrawLine(string n, datetime dt, double p, color c, int s, string d)
 {
// si ya existe, actualiza
  bool created = true;
  if(ObjectFind(0, n) == -1)
   {
    created = ObjectCreate(0, n, OBJ_TREND, 0, dt, p, TimeCurrent(), p);
    if(!created)
      return created;
   }
  else
    ObjectMove(0, n, 1, TimeCurrent(), p);
  ObjectSetDouble(0, n, OBJPROP_PRICE, p);
  ObjectSetInteger(0, n, OBJPROP_COLOR, c);
  ObjectSetInteger(0, n, OBJPROP_STYLE, s);
  ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, CRT_RAY ? 1 : 0);
  ObjectSetString(0, n, OBJPROP_TEXT, d);
  ObjectSetInteger(0, n, OBJPROP_BACK, true);

  return created;
 }
//+------------------------------------------------------------------+

