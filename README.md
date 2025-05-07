<div align="center">
    <img src="assets/logo.svg" 
            alt="Picture" 
            width="150" 
            height="150" 
            style="display: block; margin: 0 auto" />

<h1>Sora</h1>
<p>A simple, intuitive, Roblox admin script</p>
</div>

## Features
*   **Player & Chat Logs:** See live chat and who joins/leaves the game.
*   **Detailed Player Info:** View profiles, friends, groups, and items of other players.
*   **Property Editor:** Tweak various game and player settings.
*   **Voice Chat Status:** See if players are muted or unmuted in voice chat.
*   **Customizable:** Change colors, sounds, and fonts easily.

---

## Installation & How to Use

Sora is a script that you run with a Roblox script executor.

1.  **Copy the Loadstring:**
    
    ```lua
    loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/crowsyndrome/sora/refs/heads/main/main.luau"))()
    ```
    Alternatively, if you have the full script content:
2.  **Copy the Full Script:** Copy the entire Sora script code.
3.  **Execute:**
    *   Open your Roblox script executor.
    *   Paste the loadstring (or the full script) into the executor.
    *   Run/Execute the script.

You'll hear a sound and see a notification when Sora has loaded.

---

## Keybinds

*   **Open Command Bar:** `Quote` ( ` ' ` key)
*   **Click Teleport:** Hold `Left Alt` and `Left Mouse Click` to teleport.
*   **Fly Mode Controls (if fly command is active):**
    *   `E` to go up
    *   `Q` to go down

---

## Using the Command Bar

*   **Open:** Press the `Quote` ( ` ' ` ) key.
*   **Type:** Start typing what you want to do. Suggestions will appear.
*   **Autocomplete:** Press `Tab` to complete a suggestion.
*   **Run:** Press `Enter` to run the command.

To see a list of all available commands and what they do, type `commands` (or `cmds`) into the command bar and press Enter.

---

## Customization

You can change how Sora looks and feels by editing these lines at the top of the script:

```lua
local Sora = {
	keys = {
		prefix = Enum.KeyCode.Quote,    -- Key to open the command bar
		teleport = Enum.KeyCode.LeftAlt, -- Key for click teleport
	},
	customization = {
		accent = Color3.fromRGB(131, 195, 248), -- UI color
		notificationSound = "rbxassetid://89087762338808", -- Notification sound
		bootSound = "rbxassetid://136242004757394",        -- Startup sound
		font = "rbxasset://fonts/families/SourceSansPro.json", -- UI font
	},
	start = tick(),
}