//+------------------------------------------------------------------+
//|                                                    RSK.mq5       |
//|                                           Risk Management Panel   |
//+------------------------------------------------------------------+
#property copyright "Braiidev"
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0
#property description "ES: Panel de gestion de riesgo con trailing stop y Breakeven automatico."
#property description "EN: Risk management panel with auto trailing stop and Breakeven."

input group "--- RSK Panel ---"
input int    InpX          = 50;
input int    InpY          = 200;
input double InpRiskPct    = 1.0;
input double InpBenefitPct = 2.0;

#define PREFIX "RSK_"

//--- Archivo de persistencia (guarda/restaura estado entre sesiones MT5)
#define SETTINGS_FILE "RSK_settings.txt"

#define O_MAIN PREFIX "M"
#define O_BG   PREFIX "BG"

#define O_EN   PREFIX "EN"
#define O_SL   PREFIX "SL"
#define O_TP   PREFIX "TP"

#define O_TE   PREFIX "TE"
#define O_TSL  PREFIX "TS"
#define O_TTP  PREFIX "TT"

#define O_LIVE PREFIX "LIV"
#define O_FIX  PREFIX "FIX"
#define O_BUY  PREFIX "BUY"
#define O_SELL PREFIX "SEL"
#define O_SON  PREFIX "SON"
#define O_SOFF PREFIX "SOF"
#define O_TON  PREFIX "TON"
#define O_TOFF PREFIX "TOF"
#define O_HIDE PREFIX "HID"
#define O_CLS  PREFIX "CLS"

#define E_SLPCT PREFIX "SL%"
#define E_SLUSD PREFIX "SL$"
#define E_SLPIP PREFIX "SLP"
#define E_TPPCT PREFIX "TP%"
#define E_TPUSD PREFIX "TP$"
#define E_TPPIP PREFIX "TPP"

#define O_LOT  PREFIX "LOT"
#define O_LRB  PREFIX "LRB"
#define O_SEP  PREFIX "SEP"
#define O_SLL  PREFIX "SLL"
#define O_TPL  PREFIX "TPL"

#define R0  5
#define R1  31
#define R2  57
#define R3  83
#define R4  109

#define PW  310
#define PH  135
#define BH  18

#define C00  8
#define C01  53
#define C02  95
#define C03  148
#define C04  210

#define C_BG    C'47,79,79'
#define C_OFF   clrDimGray
#define C_ON    clrDarkOrange
#define C_ENTRY clrDarkGray
#define C_SL    clrCrimson
#define C_TP    clrLimeGreen
#define C_WARN  clrOrangeRed
#define C_WH    clrWhite

struct State {
   bool   open;
   bool   live;
   bool   buy;
   bool   sl_on;
   bool   tp_on;
   double sl_pct;
   double sl_usd;
   double sl_pip;
   double tp_pct;
   double tp_usd;
   double tp_pip;
   double sl_ovr;
   double tp_ovr;
   bool   hide;
   bool   dirty;
   bool   sync;
   bool   redraw;
   double last_bid;
   double en;
   double sl;
   double tp;
   double lots;
   double sl_risk;
   double sl_pct_disp;
   double tp_gain;
   double tp_pct_disp;
} g;

long   g_chart = 0;
string g_sym;
int    g_digits;
double g_point;
double g_tick_val;
double g_tick_sz;
int    g_pw;

double PipSize()
{
   return (g_digits == 5 || g_digits == 3) ? 10.0 * g_point : g_point;
}

double PricePips(double p) { return p / PipSize(); }
double PipsPrice(double p) { return p * PipSize(); }

double StepLot(double lots)
{
   double step = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_STEP);
   double min  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MIN);
   double max  = SymbolInfoDouble(g_sym, SYMBOL_VOLUME_MAX);
   lots = MathFloor(lots / step) * step;
   if(lots < min) lots = min;
   if(lots > max) lots = max;
   return lots;
}

double RiskLots(double amount, double dist)
{
   if(dist <= 0 || g_tick_sz <= 0 || g_tick_val <= 0) return 0;
   double ticks = dist / g_tick_sz;
   double per_lot = ticks * g_tick_val;
   if(per_lot <= 0) return 0;
   return StepLot(amount / per_lot);
}

double SlOffset()
{
   return 3.0 * SymbolInfoInteger(g_sym, SYMBOL_SPREAD) * g_point;
}

int PriceToY(double price)
{
   double pmax = ChartGetDouble(g_chart, CHART_PRICE_MAX, 0);
   double pmin = ChartGetDouble(g_chart, CHART_PRICE_MIN, 0);
   int h = (int)ChartGetInteger(g_chart, CHART_HEIGHT_IN_PIXELS, 0);
   if(pmax <= pmin) return 0;
   return (int)((pmax - price) / (pmax - pmin) * h);
}

void Btn(string n, string txt, int x, int y, int w, int h, color c)
{
   ObjectSetInteger(g_chart, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(g_chart, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(g_chart, n, OBJPROP_YSIZE, h);
   ObjectSetString(g_chart, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(g_chart, n, OBJPROP_COLOR, C_WH);
   ObjectSetInteger(g_chart, n, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(g_chart, n, OBJPROP_BORDER_COLOR, c);
   ObjectSetInteger(g_chart, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(g_chart, n, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(g_chart, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart, n, OBJPROP_BACK, false);
   ObjectSetInteger(g_chart, n, OBJPROP_ZORDER, 99999);
   ObjectSetString(g_chart, n, OBJPROP_FONT, "Consolas");
}

void Lbl(string n, string txt, int x, int y, color c, int fs=9)
{
   ObjectSetInteger(g_chart, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(g_chart, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(g_chart, n, OBJPROP_COLOR, c);
   ObjectSetInteger(g_chart, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(g_chart, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart, n, OBJPROP_BACK, false);
   ObjectSetInteger(g_chart, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, n, OBJPROP_ZORDER, 99999);
   ObjectSetString(g_chart, n, OBJPROP_FONT, "Consolas");
}

void Edit(string n, string txt, int x, int y, int w, int h)
{
   ObjectSetInteger(g_chart, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(g_chart, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(g_chart, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(g_chart, n, OBJPROP_YSIZE, h);
   ObjectSetString(g_chart, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(g_chart, n, OBJPROP_COLOR, C_WH);
   ObjectSetInteger(g_chart, n, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(g_chart, n, OBJPROP_BORDER_COLOR, C'80,80,80');
   ObjectSetInteger(g_chart, n, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(g_chart, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(g_chart, n, OBJPROP_READONLY, false);
   ObjectSetInteger(g_chart, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(g_chart, n, OBJPROP_BACK, false);
   ObjectSetInteger(g_chart, n, OBJPROP_ZORDER, 99999);
   ObjectSetString(g_chart, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(g_chart, n, OBJPROP_ALIGN, ALIGN_CENTER);
}

void HLine(string n, double price, color c, ENUM_LINE_STYLE style, int width, string tip="")
{
   if(ObjectFind(g_chart, n) < 0) {
      ObjectCreate(g_chart, n, OBJ_HLINE, 0, 0, 0);
      ObjectSetInteger(g_chart, n, OBJPROP_SELECTABLE, true);
      ObjectSetInteger(g_chart, n, OBJPROP_SELECTED, false);
      ObjectSetInteger(g_chart, n, OBJPROP_HIDDEN, false);
      ObjectSetInteger(g_chart, n, OBJPROP_BACK, false);
      ObjectSetInteger(g_chart, n, OBJPROP_ZORDER, 99998);
      ObjectSetInteger(g_chart, n, OBJPROP_STYLE, style);
      ObjectSetInteger(g_chart, n, OBJPROP_WIDTH, width);
   }
   ObjectSetDouble(g_chart, n, OBJPROP_PRICE, 0, price);
   ObjectSetInteger(g_chart, n, OBJPROP_COLOR, c);
   ObjectSetString(g_chart, n, OBJPROP_TOOLTIP, tip);
}

void CreateMain()
{
   ObjectCreate(g_chart, O_MAIN, OBJ_BUTTON, 0, 0, 0);
   Btn(O_MAIN, "RSK", InpX, InpY, 36, 20, clrTomato);
}

void CreatePanel()
{
   int px = g_pw;

    ObjectCreate(g_chart, O_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_XDISTANCE, px);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_YDISTANCE, InpY);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_XSIZE, PW);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_YSIZE, PH);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_BGCOLOR, C_BG);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_BORDER_COLOR, C'100,100,100');
    ObjectSetInteger(g_chart, O_BG, OBJPROP_BORDER_TYPE, BORDER_RAISED);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_BACK, false);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_ZORDER, 99999);
    ObjectSetInteger(g_chart, O_BG, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   ObjectCreate(g_chart, O_LIVE, OBJ_BUTTON, 0, 0, 0);
   Btn(O_LIVE, "Live", px + C00, InpY + R0, 35, BH, g.live ? C_ON : C_OFF);
   ObjectCreate(g_chart, O_FIX, OBJ_BUTTON, 0, 0, 0);
   Btn(O_FIX, "Fix",  px + C01, InpY + R0, 30, BH, g.live ? C_OFF : C_ON);
   ObjectCreate(g_chart, O_BUY, OBJ_BUTTON, 0, 0, 0);
   Btn(O_BUY, "Buy",  px + C03, InpY + R0, 32, BH, g.buy ? C_ON : C_OFF);
   ObjectCreate(g_chart, O_SELL, OBJ_BUTTON, 0, 0, 0);
   Btn(O_SELL, "Sell", px + C04, InpY + R0, 32, BH, g.buy ? C_OFF : C_ON);

   ObjectCreate(g_chart, O_SLL, OBJ_LABEL, 0, 0, 0);
   Lbl(O_SLL, "SL", px + C00, InpY + R1 + 3, C_WH);
   ObjectCreate(g_chart, O_SOFF, OBJ_BUTTON, 0, 0, 0);
   Btn(O_SOFF, "OFF", px + C00 + 22, InpY + R1, 28, BH, g.sl_on ? C_OFF : C_ON);
   ObjectCreate(g_chart, O_SON, OBJ_BUTTON, 0, 0, 0);
   Btn(O_SON,  "ON",  px + C00 + 53, InpY + R1, 28, BH, g.sl_on ? C_ON : C_OFF);
   ObjectCreate(g_chart, E_SLPCT, OBJ_EDIT, 0, 0, 0);
   Edit(E_SLPCT, DoubleToString(g.sl_pct, 1), px + C02, InpY + R1, 42, BH);
   ObjectCreate(g_chart, E_SLUSD, OBJ_EDIT, 0, 0, 0);
   Edit(E_SLUSD, DoubleToString(g.sl_usd, 0), px + C03, InpY + R1, 50, BH);
   ObjectCreate(g_chart, E_SLPIP, OBJ_EDIT, 0, 0, 0);
   Edit(E_SLPIP, DoubleToString(g.sl_pip, 1), px + C04, InpY + R1, 42, BH);

   ObjectCreate(g_chart, O_TPL, OBJ_LABEL, 0, 0, 0);
   Lbl(O_TPL, "TP", px + C00, InpY + R2 + 3, C_WH);
   ObjectCreate(g_chart, O_TOFF, OBJ_BUTTON, 0, 0, 0);
   Btn(O_TOFF, "OFF", px + C00 + 22, InpY + R2, 28, BH, g.tp_on ? C_OFF : C_ON);
   ObjectCreate(g_chart, O_TON, OBJ_BUTTON, 0, 0, 0);
   Btn(O_TON,  "ON",  px + C00 + 53, InpY + R2, 28, BH, g.tp_on ? C_ON : C_OFF);
   ObjectCreate(g_chart, E_TPPCT, OBJ_EDIT, 0, 0, 0);
   Edit(E_TPPCT, DoubleToString(g.tp_pct, 1), px + C02, InpY + R2, 42, BH);
   ObjectCreate(g_chart, E_TPUSD, OBJ_EDIT, 0, 0, 0);
   Edit(E_TPUSD, DoubleToString(g.tp_usd, 0), px + C03, InpY + R2, 50, BH);
   ObjectCreate(g_chart, E_TPPIP, OBJ_EDIT, 0, 0, 0);
   Edit(E_TPPIP, DoubleToString(g.tp_pip, 1), px + C04, InpY + R2, 42, BH);

   ObjectCreate(g_chart, O_LOT, OBJ_LABEL, 0, 0, 0);
   Lbl(O_LOT, "Lote: 0.00", px + C00, InpY + R3, C_ON);
   ObjectCreate(g_chart, O_SEP, OBJ_LABEL, 0, 0, 0);
   Lbl(O_SEP, "|", px + C02, InpY + R3, C'100,100,100');
   ObjectCreate(g_chart, O_LRB, OBJ_LABEL, 0, 0, 0);
   Lbl(O_LRB, "RB: 0.00", px + C02 + 15, InpY + R3, C_WH);

   ObjectCreate(g_chart, O_HIDE, OBJ_BUTTON, 0, 0, 0);
   Btn(O_HIDE, "Hide", px + C00, InpY + R4, 40, BH, C_OFF);
   ObjectCreate(g_chart, O_CLS, OBJ_BUTTON, 0, 0, 0);
   Btn(O_CLS, "Close", px + PW - 48, InpY + R4, 40, BH, clrMaroon);
}

void Del(string n)
{
   ObjectDelete(g_chart, n);
}

void DelPanel()
{
   Del(O_BG);
   Del(O_LIVE); Del(O_FIX); Del(O_BUY); Del(O_SELL);
   Del(O_SON); Del(O_SOFF); Del(O_TON); Del(O_TOFF);
   Del(O_SLL); Del(O_TPL);
   Del(E_SLPCT); Del(E_SLUSD); Del(E_SLPIP);
   Del(E_TPPCT); Del(E_TPUSD); Del(E_TPPIP);
   Del(O_LOT); Del(O_LRB); Del(O_SEP);
   Del(O_HIDE); Del(O_CLS);
}

void DelLines()
{
   Del(O_EN); Del(O_SL); Del(O_TP);
   Del(O_TE); Del(O_TSL); Del(O_TTP);
}

void DelAll()
{
   Del(O_MAIN);
   DelPanel();
   DelLines();
}

void Calc()
{
   if(g.en <= 0) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_tick_val = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_VALUE);
   g_tick_sz  = SymbolInfoDouble(g_sym, SYMBOL_TRADE_TICK_SIZE);

   double sl_dist = (g.sl_on && g.sl > 0) ? MathAbs(g.en - g.sl) : 0;

   g.lots       = 0;
   g.sl_risk    = 0;
   g.sl_pct_disp = 0;
   g.tp_gain    = 0;
   g.tp_pct_disp = 0;

   if(sl_dist > 0) {
      double risk_amt = bal * g.sl_pct / 100.0;
      double benefit_amt = bal * g.tp_pct / 100.0;

      g.lots = RiskLots(risk_amt, sl_dist);
      g.sl_risk = risk_amt;
      g.sl_pct_disp = g.sl_pct;
      g.sl_usd = risk_amt;
      g.sl_pip = PricePips(sl_dist);

      if(g.tp_on && g.lots > 0 && g_tick_val > 0 && g_tick_sz > 0) {
         if(g.live && g.tp_ovr <= 0) {
            double tp_dist = (benefit_amt / (g_tick_val * g.lots)) * g_tick_sz;
            g.tp = g.buy ? (g.en + tp_dist) : (g.en - tp_dist);
            g.tp_gain = benefit_amt;
            g.tp_pct_disp = g.tp_pct;
            g.tp_pip = PricePips(tp_dist);
            g.tp_usd = benefit_amt;
         } else {
            double tp_dist = MathAbs(g.en - g.tp);
            if(tp_dist > 0) {
               g.tp_gain = (tp_dist / g_tick_sz) * g_tick_val * g.lots;
               g.tp_pct_disp = (bal > 0) ? (g.tp_gain / bal * 100.0) : 0;
               g.tp_pip = PricePips(tp_dist);
               g.tp_usd = g.tp_gain;
               g.tp_pct = g.tp_pct_disp;
            }
         }
      }

   }

   // TP on but lots=0 (SL off or distance too small): show stored panel values
   if(g.tp_on && g.lots <= 0) {
      g.tp_pct_disp = g.tp_pct;
      g.tp_gain = g.tp_usd;
      if(g.tp > 0) g.tp_pip = PricePips(MathAbs(g.en - g.tp));
   }
}

void Update()
{
   if(!g.open) return;
   int px = g_pw;
   int cw = (int)ChartGetInteger(g_chart, CHART_WIDTH_IN_PIXELS);

   Calc();

   if(g.sync) {
      g.sync = false;
      ObjectSetString(g_chart, E_SLPCT, OBJPROP_TEXT, DoubleToString(g.sl_pct, 1));
      ObjectSetString(g_chart, E_SLUSD, OBJPROP_TEXT, DoubleToString(g.sl_usd, 0));
      ObjectSetString(g_chart, E_SLPIP, OBJPROP_TEXT, DoubleToString(g.sl_pip, 1));
      ObjectSetString(g_chart, E_TPPCT, OBJPROP_TEXT, DoubleToString(g.tp_pct, 1));
      ObjectSetString(g_chart, E_TPUSD, OBJPROP_TEXT, DoubleToString(g.tp_usd, 0));
      ObjectSetString(g_chart, E_TPPIP, OBJPROP_TEXT, DoubleToString(g.tp_pip, 1));
   }

   if(ObjectFind(g_chart, O_EN) >= 0)
      ObjectSetDouble(g_chart, O_EN, OBJPROP_PRICE, 0, g.en);
   if(g.sl_on && ObjectFind(g_chart, O_SL) >= 0)
      ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl);
   if(g.tp_on && ObjectFind(g_chart, O_TP) >= 0)
      ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);

   double sl_pips = 0, tp_pips = 0;
   if(g.sl_on && g.sl > 0) sl_pips = PricePips(MathAbs(g.en - g.sl));
   if(g.tp_on && g.tp > 0) tp_pips = PricePips(MathAbs(g.en - g.tp));

   double rr = 0;
   double sl_d = (g.sl_on && g.sl > 0) ? MathAbs(g.en - g.sl) : 0;
   double tp_d = (g.tp_on && g.tp > 0) ? MathAbs(g.en - g.tp) : 0;
   if(sl_d > 0 && tp_d > 0) rr = tp_d / sl_d;
   if(!g.hide) {
      string en_txt = StringFormat("%.2f:1|%.2f|%."+IntegerToString(g_digits)+"f", rr, g.lots, g.en);
      int en_y = PriceToY(g.en) - 4;
      if(ObjectFind(g_chart, O_TE) < 0) {
         ObjectCreate(g_chart, O_TE, OBJ_LABEL, 0, 0, 0);
         Lbl(O_TE, en_txt, cw - 195, en_y, C_ENTRY, 8);
      } else {
         Lbl(O_TE, en_txt, cw - 195, en_y, C_ENTRY, 8);
      }

      if(g.sl_on && g.sl > 0) {
         string sl_txt = StringFormat("%.0fp|$%.2f|%.2f%%", sl_pips, g.sl_risk, g.sl_pct_disp);
         int sl_y = PriceToY(g.sl) - 4;
         if(ObjectFind(g_chart, O_TSL) < 0) {
            ObjectCreate(g_chart, O_TSL, OBJ_LABEL, 0, 0, 0);
            Lbl(O_TSL, sl_txt, cw - 155, sl_y, C_SL, 8);
         } else {
            Lbl(O_TSL, sl_txt, cw - 155, sl_y, C_SL, 8);
         }
      }

      if(g.tp_on && g.tp > 0) {
         string tp_txt = StringFormat("%.0fp|$%.2f|%.2f%%", tp_pips, g.tp_gain, g.tp_pct_disp);
         int tp_y = PriceToY(g.tp) - 4;
         if(ObjectFind(g_chart, O_TTP) < 0) {
            ObjectCreate(g_chart, O_TTP, OBJ_LABEL, 0, 0, 0);
            Lbl(O_TTP, tp_txt, cw - 155, tp_y, C_TP, 8);
         } else {
            Lbl(O_TTP, tp_txt, cw - 155, tp_y, C_TP, 8);
         }
      }
   }

   Lbl(O_LOT, StringFormat("Lote: %.2f", g.lots), px + C00, InpY + R3, g.lots > 0 ? C_ON : C_WARN);
   Lbl(O_LRB, StringFormat("RB: %.2f", rr), px + C02 + 15, InpY + R3, C_WH);
}

void OpenPanel()
{
   if(g.open) return;
   g.open = true;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   g.en = g.buy ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
   g.sl = 0;
   g.tp = 0;

   g.sl_pct = InpRiskPct;
   g.sl_usd = bal * InpRiskPct / 100.0;
   g.sl_pip = PricePips(SlOffset());
   g.tp_pct = InpBenefitPct;
   g.tp_usd = bal * InpBenefitPct / 100.0;
   g.tp_pip = g.sl_pip * 2.0;
   g.sl_ovr = 0;
   g.tp_ovr = 0;

   g.dirty = true;
   g.sync = true;

   // Create HLines BEFORE panel so panel always draws on top
   HLine(O_EN, g.en, C_ENTRY, STYLE_DOT, 1, "Entry");
   HLine(O_SL, 0, clrNONE, STYLE_SOLID, 2, "Stop Loss");
   HLine(O_TP, 0, clrNONE, STYLE_SOLID, 2, "Take Profit");

   CreatePanel();
   Update();
   ChartRedraw(g_chart);
}

void ClosePanel()
{
   g.open    = false;
   g.sl_on   = false;
   g.tp_on   = false;
   g.hide    = false;
   g.en      = 0;
   g.sl      = 0;
   g.tp      = 0;
   g.lots    = 0;
   g.sl_risk = 0;
   g.sl_pct_disp = 0;
   g.tp_gain = 0;
   g.tp_pct_disp = 0;

   DelPanel();
   DelLines();

   CreateMain();
   ChartRedraw(g_chart);
}

//+------------------------------------------------------------------+
//| Sincroniza color de todos los botones del panel segun estado      |
//+------------------------------------------------------------------+
void SyncButtons()
{
   Btn(O_LIVE, "Live", g_pw + C00, InpY + R0, 35, BH, g.live ? C_ON : C_OFF);
   Btn(O_FIX,  "Fix",  g_pw + C01, InpY + R0, 30, BH, g.live ? C_OFF : C_ON);
   Btn(O_BUY,  "Buy",  g_pw + C03, InpY + R0, 32, BH, g.buy ? C_ON : C_OFF);
   Btn(O_SELL, "Sell", g_pw + C04, InpY + R0, 32, BH, g.buy ? C_OFF : C_ON);

   Btn(O_SON,  "ON",   g_pw + C00 + 53, InpY + R1, 28, BH, g.sl_on ? C_ON : C_OFF);
   Btn(O_SOFF, "OFF",  g_pw + C00 + 22, InpY + R1, 28, BH, g.sl_on ? C_OFF : C_ON);

   Btn(O_TON,  "ON",   g_pw + C00 + 53, InpY + R2, 28, BH, g.tp_on ? C_ON : C_OFF);
   Btn(O_TOFF, "OFF",  g_pw + C00 + 22, InpY + R2, 28, BH, g.tp_on ? C_OFF : C_ON);

   Btn(O_HIDE, g.hide ? "Show" : "Hide", g_pw + C00, InpY + R4, 40, BH, C_OFF);
}

//+------------------------------------------------------------------+
//| Guarda configuracion completa del panel RSK                       |
//+------------------------------------------------------------------+
void SaveSettings()
{
   int handle = FileOpen(SETTINGS_FILE, FILE_TXT|FILE_CSV|FILE_WRITE, ",");
   if(handle == INVALID_HANDLE) return;

   FileWrite(handle,
      g.open,            // 0: el panel estaba abierto?
      g.live,            // 1: modo Live/Fix
      g.buy,             // 2: direccion Buy/Sell
      g.sl_on,           // 3: SL activo?
      g.tp_on,           // 4: TP activo?
      g.hide,            // 5: lineas ocultas?
      g.sl_pct,          // 6: SL en % del balance
      g.sl_usd,          // 7: SL en USD
      g.sl_pip,          // 8: SL en pips
      g.tp_pct,          // 9: TP en % del balance
      g.tp_usd,          //10: TP en USD
      g.tp_pip,          //11: TP en pips
      g.sl_ovr,          //12: SL override en precio
      g.tp_ovr,          //13: TP override en precio
      g.en,              //14: precio de entrada
      g.sl,              //15: precio de Stop Loss
      g.tp               //16: precio de Take Profit
   );

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Restaura configuracion del panel RSK desde archivo                |
//+------------------------------------------------------------------+
void LoadSettings()
{
   int handle = FileOpen(SETTINGS_FILE, FILE_TXT|FILE_CSV|FILE_READ, ",");
   if(handle == INVALID_HANDLE) return;

   bool was_open     = (bool)FileReadNumber(handle);
   g.live            = (bool)FileReadNumber(handle);
   g.buy             = (bool)FileReadNumber(handle);
   g.sl_on           = (bool)FileReadNumber(handle);
   g.tp_on           = (bool)FileReadNumber(handle);
   g.hide            = (bool)FileReadNumber(handle);
   g.sl_pct          = FileReadNumber(handle);
   g.sl_usd          = FileReadNumber(handle);
   g.sl_pip          = FileReadNumber(handle);
   g.tp_pct          = FileReadNumber(handle);
   g.tp_usd          = FileReadNumber(handle);
   g.tp_pip          = FileReadNumber(handle);
   g.sl_ovr          = FileReadNumber(handle);
   g.tp_ovr          = FileReadNumber(handle);
   g.en              = FileReadNumber(handle);
   g.sl              = FileReadNumber(handle);
   g.tp              = FileReadNumber(handle);

   FileClose(handle);

   // Recrea el panel completo si estaba abierto al salir
   if(!was_open) return;

   // Valida que los precios guardados tengan sentido en el simbolo actual
   double curr = g.buy ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(curr > 0 && MathAbs(g.en - curr) > curr * 0.2)
   {
      Print("RSK: Precios guardados difieren >20% del precio actual. No se restaura el panel.");
      g.open = false;
      return;
   }

   Del(O_MAIN);              // Reemplaza el boton main por el panel completo
   g.open = true;

   // Crea las lineas de precio en el grafico
   HLine(O_EN, g.en, C_ENTRY, STYLE_DOT, 1, "Entry");
   HLine(O_SL, g.sl, g.sl_on ? C_SL : clrNONE, STYLE_SOLID, 2, "Stop Loss");
   HLine(O_TP, g.tp, g.tp_on ? C_TP : clrNONE, STYLE_SOLID, 2, "Take Profit");

   CreatePanel();
   SyncButtons();

   g.dirty   = true;
   g.sync    = true;
   g.redraw  = true;
   g.last_bid = 0;

   TickUpdate();
   ChartRedraw(g_chart);
}

//+------------------------------------------------------------------+
void TickUpdate()
{
   if(!g.open) return;

   double bid = SymbolInfoDouble(g_sym, SYMBOL_BID);
   if(bid <= 0) return;

   bool bid_changed = (bid != g.last_bid);
   g.last_bid = bid;

   if(g.live) {
      g.en = g.buy ? SymbolInfoDouble(g_sym, SYMBOL_ASK) : bid;
      if(!bid_changed && !g.dirty) return;

      if(g.sl_on) {
         double offset = (g.sl_ovr > 0) ? g.sl_ovr : SlOffset();
         g.sl = g.buy ? (g.en - offset) : (g.en + offset);
      }
      if(g.tp_on && g.tp_ovr > 0) {
         g.tp = g.buy ? (g.en + g.tp_ovr) : (g.en - g.tp_ovr);
      }
   } else {
      bool changed = g.dirty;
      double cur_en = ObjectGetDouble(g_chart, O_EN, OBJPROP_PRICE, 0);
      if(cur_en != g.en && cur_en > 0) {
         double diff = cur_en - g.en;
         g.en = cur_en;
         if(g.sl_on && g.sl > 0) { g.sl += diff; ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl); }
         if(g.tp_on && g.tp > 0) { g.tp += diff; ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp); }
         changed = true;
      }
      if(g.sl_on && g.sl > 0) {
         double cur_sl = ObjectGetDouble(g_chart, O_SL, OBJPROP_PRICE, 0);
         if(cur_sl != g.sl && cur_sl > 0) { g.sl = cur_sl; changed = true; }
      }
      if(g.tp_on && g.tp > 0) {
         double cur_tp = ObjectGetDouble(g_chart, O_TP, OBJPROP_PRICE, 0);
         if(cur_tp != g.tp && cur_tp > 0) { g.tp = cur_tp; changed = true; }
      }
      if(!changed && !bid_changed) return;

       // auto-disable if dragged to wrong side of entry
       if(g.sl_on && g.sl > 0) {
          if((g.buy && g.sl >= g.en) || (!g.buy && g.sl <= g.en)) {
             g.sl_on = false; g.sl = 0;
             ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, clrNONE); Del(O_TSL);
             ObjectSetInteger(g_chart, O_SOFF, OBJPROP_BGCOLOR, C_ON);
             ObjectSetInteger(g_chart, O_SOFF, OBJPROP_BORDER_COLOR, C_ON);
             ObjectSetInteger(g_chart, O_SON, OBJPROP_BGCOLOR, C_OFF);
             ObjectSetInteger(g_chart, O_SON, OBJPROP_BORDER_COLOR, C_OFF);
          }
       }
       if(g.tp_on && g.tp > 0) {
          if((g.buy && g.tp <= g.en) || (!g.buy && g.tp >= g.en)) {
             g.tp_on = false; g.tp = 0;
             ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, clrNONE); Del(O_TTP);
             ObjectSetInteger(g_chart, O_TOFF, OBJPROP_BGCOLOR, C_ON);
             ObjectSetInteger(g_chart, O_TOFF, OBJPROP_BORDER_COLOR, C_ON);
             ObjectSetInteger(g_chart, O_TON, OBJPROP_BGCOLOR, C_OFF);
             ObjectSetInteger(g_chart, O_TON, OBJPROP_BORDER_COLOR, C_OFF);
          }
       }
   }

   g.dirty = false;
   Calc();

   if(!g.hide) {
      ObjectSetDouble(g_chart, O_EN, OBJPROP_PRICE, 0, g.en);
      ObjectSetInteger(g_chart, O_EN, OBJPROP_COLOR, C_ENTRY);
      if(g.sl_on && g.sl > 0) {
         ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl);
         ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, C_SL);
      } else {
         ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, clrNONE);
      }
      if(g.tp_on && g.tp > 0) {
         ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
         ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, C_TP);
      } else {
         ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, clrNONE);
      }
   } else {
      ObjectSetInteger(g_chart, O_EN, OBJPROP_COLOR, clrNONE);
      ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, clrNONE);
      ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, clrNONE);
   }

   Update();
   if(g.redraw) {
      ChartRedraw(g_chart);
      g.redraw = false;
   }
}

int OnInit()
{
   g_chart   = ChartID();
   g_sym     = _Symbol;
   g_point   = SymbolInfoDouble(g_sym, SYMBOL_POINT);
   g_digits  = (int)SymbolInfoInteger(g_sym, SYMBOL_DIGITS);
   g_pw      = InpX;

   g.open    = false;
   g.live    = true;
   g.buy     = true;
   g.sl_on   = false;
   g.tp_on   = false;
   g.hide    = false;
   g.en      = 0;
   g.sl      = 0;
   g.tp      = 0;
   g.lots    = 0;
   g.sl_risk = 0;
   g.sl_pct_disp = 0;
   g.tp_gain = 0;
   g.tp_pct_disp = 0;
   g.sl_pct  = InpRiskPct;
   g.sl_usd  = 0;
   g.sl_pip  = 0;
   g.tp_pct  = InpBenefitPct;
   g.tp_usd  = 0;
   g.tp_pip  = 0;
   g.sl_ovr  = 0;
   g.tp_ovr  = 0;
   g.dirty   = true;
   g.sync    = false;
   g.redraw  = false;
   g.last_bid = 0;

   DelAll();
   CreateMain();

   // Restaura el panel completo si estaba abierto al cerrar MT5
   LoadSettings();

   EventSetMillisecondTimer(200);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveSettings();
   DelAll();
}

void OnTimer()
{
   g.sync = false; g.redraw = false;
   TickUpdate();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == O_MAIN) {
         if(!g.open) OpenPanel();
         else ClosePanel();
         return;
      }

      if(!g.open) return;

      if(sparam == O_LIVE && !g.live) {
         g.live = true;
         g.sl_ovr = (g.sl_on && g.sl > 0) ? MathAbs(g.en - g.sl) : 0;
         g.tp_ovr = (g.tp_on && g.tp > 0) ? MathAbs(g.en - g.tp) : 0;
         Btn(O_LIVE, "Live", g_pw + C00, InpY + R0, 35, BH, C_ON);
         Btn(O_FIX, "Fix",  g_pw + C01, InpY + R0, 30, BH, C_OFF);
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
         return;
      }
      if(sparam == O_FIX && g.live) {
         g.live = false;
         Btn(O_FIX, "Fix",  g_pw + C01, InpY + R0, 30, BH, C_ON);
         Btn(O_LIVE, "Live", g_pw + C00, InpY + R0, 35, BH, C_OFF);
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
         return;
      }

      if(sparam == O_BUY && !g.buy) {
         g.buy = true;
         ObjectSetInteger(g_chart, O_BUY, OBJPROP_BGCOLOR, C_ON);
         ObjectSetInteger(g_chart, O_BUY, OBJPROP_BORDER_COLOR, C_ON);
         ObjectSetInteger(g_chart, O_SELL, OBJPROP_BGCOLOR, C_OFF);
         ObjectSetInteger(g_chart, O_SELL, OBJPROP_BORDER_COLOR, C_OFF);
         if(!g.live) {
            if(g.sl_on && g.sl > 0) {
               double dist = MathAbs(g.en - g.sl);
               g.sl = g.en - dist;
               ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl);
            }
            if(g.tp_on && g.tp > 0) {
               double dist = MathAbs(g.en - g.tp);
               g.tp = g.en + dist;
               ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
            }
         }
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
         return;
      }
      if(sparam == O_SELL && g.buy) {
         g.buy = false;
         ObjectSetInteger(g_chart, O_SELL, OBJPROP_BGCOLOR, C_ON);
         ObjectSetInteger(g_chart, O_SELL, OBJPROP_BORDER_COLOR, C_ON);
         ObjectSetInteger(g_chart, O_BUY, OBJPROP_BGCOLOR, C_OFF);
         ObjectSetInteger(g_chart, O_BUY, OBJPROP_BORDER_COLOR, C_OFF);
         if(!g.live) {
            if(g.sl_on && g.sl > 0) {
               double dist = MathAbs(g.en - g.sl);
               g.sl = g.en + dist;
               ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl);
            }
            if(g.tp_on && g.tp > 0) {
               double dist = MathAbs(g.en - g.tp);
               g.tp = g.en - dist;
               ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
            }
         }
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
         return;
      }

      if(sparam == O_SON && !g.sl_on) {
         g.sl_on = true;
         g.sl_ovr = 0;
         Btn(O_SON, "ON",  g_pw + C00 + 53, InpY + R1, 28, BH, C_ON);
         Btn(O_SOFF, "OFF", g_pw + C00 + 22, InpY + R1, 28, BH, C_OFF);
         g.sl = g.buy ? (g.en - SlOffset()) : (g.en + SlOffset());
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
         return;
      }
       if(sparam == O_SOFF && g.sl_on) {
          g.sl_on = false;
          Btn(O_SOFF, "OFF", g_pw + C00 + 22, InpY + R1, 28, BH, C_ON);
          Btn(O_SON, "ON",  g_pw + C00 + 53, InpY + R1, 28, BH, C_OFF);
          ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, clrNONE);
          Del(O_TSL);
          g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
          return;
       }

      if(sparam == O_TON && !g.tp_on) {
         g.tp_on = true;
         g.tp_ovr = 0;
         Btn(O_TON, "ON",  g_pw + C00 + 53, InpY + R2, 28, BH, C_ON);
         Btn(O_TOFF, "OFF", g_pw + C00 + 22, InpY + R2, 28, BH, C_OFF);
         if(g.sl_on && g.sl > 0) {
            double sl_dist = MathAbs(g.en - g.sl);
            g.tp = g.buy ? (g.en + sl_dist * 2.0) : (g.en - sl_dist * 2.0);
         } else {
            double offset = SlOffset() * 2.0;
            g.tp = g.buy ? (g.en + offset) : (g.en - offset);
         }
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
         return;
      }
       if(sparam == O_TOFF && g.tp_on) {
          g.tp_on = false;
          Btn(O_TOFF, "OFF", g_pw + C00 + 22, InpY + R2, 28, BH, C_ON);
          Btn(O_TON, "ON",  g_pw + C00 + 53, InpY + R2, 28, BH, C_OFF);
          ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, clrNONE);
          Del(O_TTP);
          g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
          return;
       }

       if(sparam == O_HIDE) {
          g.hide = !g.hide;
          Btn(O_HIDE, g.hide ? "Show" : "Hide", g_pw + C00, InpY + R4, 40, BH, C_OFF);
          if(g.hide) {
             ObjectSetInteger(g_chart, O_EN, OBJPROP_COLOR, clrNONE);
             ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, clrNONE);
             ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, clrNONE);
             Del(O_TE); Del(O_TSL); Del(O_TTP);
          } else {
             ObjectSetInteger(g_chart, O_EN, OBJPROP_COLOR, C_ENTRY);
             ObjectSetDouble(g_chart, O_EN, OBJPROP_PRICE, 0, g.en);
             if(g.sl_on && g.sl > 0) {
                ObjectSetInteger(g_chart, O_SL, OBJPROP_COLOR, C_SL);
                ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl);
             }
             if(g.tp_on && g.tp > 0) {
                ObjectSetInteger(g_chart, O_TP, OBJPROP_COLOR, C_TP);
                ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
             }
          }
          g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
          return;
       }

      if(sparam == O_CLS) {
         ClosePanel();
         return;
      }
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == E_SLPCT)
   {
      double val = StringToDouble(ObjectGetString(g_chart, E_SLPCT, OBJPROP_TEXT));
      if(val > 0) { g.sl_pct = val; g.sync = true; g.redraw = true; g.dirty = true; TickUpdate(); }
      return;
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == E_SLUSD)
   {
      double val = StringToDouble(ObjectGetString(g_chart, E_SLUSD, OBJPROP_TEXT));
      if(val > 0) {
         g.sl_usd = val;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         if(bal > 0) g.sl_pct = val / bal * 100.0;
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == E_SLPIP)
   {
      double val = StringToDouble(ObjectGetString(g_chart, E_SLPIP, OBJPROP_TEXT));
      if(val > 0) {
         g.sl_pip = val;
         if(g.sl_on) {
            double pd = PipsPrice(g.sl_pip);
            g.sl_ovr = pd;
            g.sl = g.buy ? (g.en - pd) : (g.en + pd);
            if(ObjectFind(g_chart, O_SL) >= 0)
               ObjectSetDouble(g_chart, O_SL, OBJPROP_PRICE, 0, g.sl);
         }
         g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
      }
      return;
   }

   if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == E_TPPCT)
   {
      double val = StringToDouble(ObjectGetString(g_chart, E_TPPCT, OBJPROP_TEXT));
      if(val > 0) {
         g.tp_pct = val;
         double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         double benefit_amt = bal * val / 100.0;
         if(g.tp_on && benefit_amt > 0 && g_tick_val > 0 && g_tick_sz > 0) {
             if(!g.live && g.lots > 0) {
                double tp_dist = (benefit_amt / (g_tick_val * g.lots)) * g_tick_sz;
                g.tp_ovr = tp_dist;
                g.tp = g.buy ? (g.en + tp_dist) : (g.en - tp_dist);
                if(ObjectFind(g_chart, O_TP) >= 0)
                   ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
             } else {
                g.tp_ovr = 0;
             }
          }
          g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
       }
       return;
    }

    if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == E_TPUSD)
    {
       double val = StringToDouble(ObjectGetString(g_chart, E_TPUSD, OBJPROP_TEXT));
       if(val > 0) {
          g.tp_usd = val;
          double bal = AccountInfoDouble(ACCOUNT_BALANCE);
          if(bal > 0) g.tp_pct = val / bal * 100.0;
          if(g.tp_on && g_tick_val > 0 && g_tick_sz > 0) {
              if(!g.live && g.lots > 0) {
                 double tp_dist = (val / (g_tick_val * g.lots)) * g_tick_sz;
                 g.tp_ovr = tp_dist;
                 g.tp = g.buy ? (g.en + tp_dist) : (g.en - tp_dist);
                 if(ObjectFind(g_chart, O_TP) >= 0)
                    ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
              } else {
                 g.tp_ovr = 0;
             }
          }
          g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
       }
       return;
    }

    if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == E_TPPIP)
    {
       double val = StringToDouble(ObjectGetString(g_chart, E_TPPIP, OBJPROP_TEXT));
       if(val > 0) {
          g.tp_pip = val;
          if(g.tp_on) {
             double pd = PipsPrice(g.tp_pip);
             g.tp_ovr = pd;
             g.tp = g.buy ? (g.en + pd) : (g.en - pd);
             if(ObjectFind(g_chart, O_TP) >= 0)
                ObjectSetDouble(g_chart, O_TP, OBJPROP_PRICE, 0, g.tp);
          }
          g.sync = true; g.redraw = true; g.dirty = true; TickUpdate();
       }
       return;
    }

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      if(g.open) Update();
   }
}

int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[],
                const double &close[], const long &tick_volume[],
                const long &volume[], const int &spread[])
{
   return rates_total;
}
