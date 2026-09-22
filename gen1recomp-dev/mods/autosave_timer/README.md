# ⏱️ Autosave Timer for Gen1Recomp

A lightweight quality-of-life mod for **Pokémon Generation 1 Recompilation** (`gen1recomp`) that automatically saves your game progress on a customizable timer while protecting you from bad save states.

---

## ✨ Features

- **🔛 On/Off Toggle:** Turn the entire autosave timer on or off from Options.
- **⏱️ Configurable Intervals:** Set your preferred autosave frequency (1, 3, or 5 minutes).
- **🛡️ Battle Protection:** Automatically detects active battles and skips saving to prevent corrupted, stuck, or unsafe save states.
- **🔄 Auto-Update Integration:** Native support for the `gen1recomp` launcher update system (Check for Updates / Version history).
- **🚀 Ultra Lightweight:** Negligible performance footprint written in optimized Lua.

---

## 📥 Installation

1. Download the latest release (`autosave_timer-0.1.3.zip` or `.modpkg`).
2. Open the **Gen1Recomp** launcher.
3. Go to the **Mods** section.
4. Drag and drop the downloaded archive into the window.
5. Enable the mod and launch your game!

---

## ⚙️ Configuration & Behavior

The mod automatically runs in the background during active gameplay:
- **AUTOSAVE (Options):** Master on/off toggle for the whole timer.
- Timer ticks only while in valid overworld states.
- If a timer triggers during a battle, dialogue, or menu transition, the save is safely postponed until you return to the overworld.

---

## 🔗 Project & License

- **Author:** [blackwing182](https://github.com/blackwing182)
- **Repository:** [blackwing182/autosave_timer](https://github.com/blackwing182/autosave_timer)
- **Compatibility:** Pokémon Gen 1 Recomp (`>=0.0.0-dev <1.0.0`)
