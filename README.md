# Jerry Pets

Jerry from *Tom and Jerry* as a standalone Windows desktop pet and Codex pet (`spriteVersionNumber: 2`).

## Supported Actions

- **Stand** (`stand` / row `0`)
- **Walk** (`walk-right` / row `1`, `walk-left` / row `2`)
- **Dizzy** (`dizzy` / rows `3–5`, 24-frame spin triggered on **double left-click**)
- **Run** (`run-right` / row `6`, `run-left` / row `7`, fast sprint during roam & cursor chase)
- **Hungry** (`hungry` / rows `8–10`, 24-frame hungry begging & tummy-rubbing animation)

## Usage

### Standalone Windows Desktop Pet

Double-click `run-jerry.bat` or run via PowerShell (defaults to `0.5x` size):

```powershell
.\run-jerry.ps1
```

Interactions:
- **Left-click & drag**: Move Jerry anywhere on the screen
- **Double left-click**: Trigger the **Dizzy** spin animation
- **Right-click**: Open menu to switch roaming modes (**Free Roam Anywhere**, **Roam Along Bottom**, **Chase Cursor**), lock a single action (`stand`, `walk-right`, `walk-left`, `run-right`, `run-left`, `dizzy`, `hungry`), resize (`0.5x` default – `1.5x`), or exit

### Install into Codex

```powershell
.\install.ps1
```
