local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local BlurredGui = {}
BlurredGui.__index = BlurredGui

local function ensureDof()
	local dof = Lighting:FindFirstChild("BoomboxBlurDOF")
	if not dof then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "BoomboxBlurDOF"
		dof.FarIntensity = 0
		dof.FocusDistance = 0.05
		dof.InFocusRadius = 500
		dof.NearIntensity = 0.35
		dof.Parent = Lighting
	end
	return dof
end

function BlurredGui.new(guiObject, shape)
	local self = setmetatable({}, BlurredGui)
	self.GuiObject = guiObject
	self.Shape = shape or "Rectangle"
	self.DOF = ensureDof()

	self.GlassPart = Instance.new("Part")
	self.GlassPart.Name = "BoomboxGlassBlurPart"
	self.GlassPart.Anchored = true
	self.GlassPart.CanCollide = false
	self.GlassPart.CastShadow = false
	self.GlassPart.Transparency = 0.98
	self.GlassPart.Material = Enum.Material.Glass
	self.GlassPart.Size = Vector3.new(1, 1, 0.05)
	self.GlassPart.Parent = workspace.CurrentCamera

	self._conn = RunService.RenderStepped:Connect(function()
		if not self.GuiObject or not self.GuiObject.Parent or not workspace.CurrentCamera then return end
		local absPos = self.GuiObject.AbsolutePosition
		local absSize = self.GuiObject.AbsoluteSize
		local centerX = absPos.X + absSize.X * 0.5
		local centerY = absPos.Y + absSize.Y * 0.5
		local ray = workspace.CurrentCamera:ViewportPointToRay(centerX, centerY, 5)
		self.GlassPart.CFrame = CFrame.new(ray.Origin + ray.Direction * 5, ray.Origin + ray.Direction * 6)
		self.GlassPart.Size = Vector3.new(math.max(absSize.X / 50, 0.1), math.max(absSize.Y / 50, 0.1), 0.05)
	end)

	return self
end

function BlurredGui:Destroy()
	if self._conn then self._conn:Disconnect(); self._conn = nil end
	if self.GlassPart then self.GlassPart:Destroy(); self.GlassPart = nil end
end

return BlurredGui
