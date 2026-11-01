--!strict
-- Play-mode helper for the thumbnail scene (Config.BuildThumbnailScene).
-- Locks the camera to Workspace.ThumbnailScene.ThumbnailCamera and hides
-- all UI, so a Play (F5) test looks the same as Run (F8).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local ThumbnailView = {}

local function hideCoreUi()
	-- Core UI can refuse this for a moment after joining, so retry briefly
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
		end)
		if ok then
			return
		end
		task.wait(0.25)
	end
end

function ThumbnailView.start()
	local player = Players.LocalPlayer
	task.spawn(hideCoreUi)

	local scene = workspace:WaitForChild("ThumbnailScene", 60)
	local sceneCamera = scene and scene:WaitForChild("ThumbnailCamera", 30)
	if not sceneCamera or not sceneCamera:IsA("Camera") then
		warn("[Noodle Bonk] No thumbnail scene found. Is Config.BuildThumbnailScene on?")
		return
	end

	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = sceneCamera.CFrame
			camera.FieldOfView = sceneCamera.FieldOfView
		end
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			for _, gui in playerGui:GetChildren() do
				if gui:IsA("ScreenGui") then
					gui.Enabled = false
				end
			end
		end
	end)
end

return ThumbnailView
