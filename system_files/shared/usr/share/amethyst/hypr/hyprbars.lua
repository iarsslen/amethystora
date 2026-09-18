-- Amethyst window title bars (hyprbars), loaded from ~/.config/hypr/hyprland.lua.
-- Remove the line that loads this file there to go without title bars.

hl.plugin.load("/usr/lib64/hyprland/libhyprbars.so")

-- hl.plugin.hyprbars only exists once Hyprland has loaded the plugin and reloaded the config
if not hl.plugin.hyprbars then
	return
end

hl.config({
	plugin = {
		hyprbars = {
			bar_height = 28,
			bar_color = "rgb(211f26)",
			col = {
				text = "rgb(e6e0e9)",
			},
			bar_text_size = 11,
			bar_text_weight = "medium",
			bar_part_of_window = true,
			bar_precedence_over_border = true,
			bar_padding = 10,
			bar_button_padding = 8,
			on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
		},
	},
})

-- Buttons are placed right to left. Icons are Nerd Font glyphs (nerd-fonts is part of the image).
hl.plugin.hyprbars.add_button({
	bg_color = "rgb(f2b8b5)",
	fg_color = "rgb(601410)",
	size = 16,
	icon = "󰖭",
	action = "hyprctl dispatch 'hl.dsp.window.close()'",
})

hl.plugin.hyprbars.add_button({
	bg_color = "rgb(d0bcff)",
	fg_color = "rgb(381e72)",
	size = 16,
	icon = "󰖯",
	action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
})

hl.plugin.hyprbars.add_button({
	bg_color = "rgb(ccc2dc)",
	fg_color = "rgb(332d41)",
	size = 16,
	icon = "󰖲",
	action = [[hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })']],
})
