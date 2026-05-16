local M = {}

M.enabled = false

M.counter = 1
M.launch_cmd = 'xdotool set_window --name "Dofus %s" "$(xdotool search --pid %s)"'

M.characters = {
	"Rejecter",
	"Draintouch",
	"Reminiscer",
	"Traumafactory",
	"Memoryfracture",
	"Miserymaker",
	"Sayer",
	"Dissipate",
}

function M:reset_counter()
	self.counter = 1
	hl.notification.create({
		text = "Dofus Launch Counter Reset",
		duration = 2000,
		color = require("themes.macchiato").mauve,
	})
end

function M:increment_counter()
	self.counter = self.counter + 1
end

function M:toggle_enable()
	if self.enabled then
		self.enabled = false
		hl.notification.create({
			text = "Dofus Launch Disabled",
			duration = 2000,
			color = require("themes.macchiato").mauve,
		})
	else
		self.enabled = true
		hl.notification.create({
			text = "Dofus Launch Enabled",
			duration = 2000,
			color = require("themes.macchiato").mauve,
		})
	end
end

hl.on(

	"window.open",
	---@param w HL.Window
	function(w)
		if M.enabled then
			if w.class == "Dofus.x64" and M.counter <= #M.characters then
				local title = M.characters[M.counter]
				local cmd = M.launch_cmd:format(title, w.pid)
				hl.dispatch(hl.dsp.exec_raw(cmd))
				M:increment_counter()
			end

			if M.counter > #M.characters then
				M:reset_counter()
				M:toggle_enable()
			end
		end
	end
)

return M
