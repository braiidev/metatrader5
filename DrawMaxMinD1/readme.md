# 📈 CRTSession.mq5

**CRTSession** is a lightweight MetaTrader 5 indicator that plots and updates the **daily candle range** (High/Low) for the current, previous, and last daily sessions.

---

## ✨ Features
- Automatically draws three sets of horizontal range lines:
  - **Current** day range  
  - **Previous** day range  
  - **Last** (2 days ago) range  
- Lines are dynamically **updated** as new candles form.  
- Clean, efficient structure using a custom `candleRange` struct.  
- Fully customizable:
  - `CR_style` → line style  
  - `CR_color` → line color  
  - `CRT_RAY`  → extend lines to the right  

---

## ⚙️ Inputs

| Parameter | Type | Description |
|------------|------|-------------|
| `CR_style` | `int` | Line style (solid, dashed, etc.) |
| `CR_color` | `color` | Line color |
| `CRT_RAY`  | `bool` | Whether to extend line to the right |

---

## 🧩 How It Works

1. On initialization (`OnInit`), it loads 3 candle ranges:  
   - Current day (`shift=0`)  
   - Previous day (`shift=1`)  
   - Last day (`shift=2`)  
2. Each range stores prices, timestamps, and graphical object names.  
3. `OnCalculate` continuously updates the line positions when prices change.

---

## 📄 License
Free to use and modify for educational or personal purposes.  
Developed by **Braiidev**.

