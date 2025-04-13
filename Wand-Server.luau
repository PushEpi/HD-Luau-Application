--{{Variables}}--
local tool:Tool = script.Parent
local player:Player = tool.Parent.Parent -- Tool > Backpack > Player
local char:Model = player.Character or player.CharacterAdded:Wait()
local remote:RemoteEvent = tool:WaitForChild("RemoteEvent")
local castOrigin:Attachment = tool:WaitForChild("Handle"):WaitForChild("CastOrigin") -- Where we casting from
local castDebounce:boolean = false -- Debounce for casting spells
local changeDebounce:boolean = false -- Debounce for changing spells
local currentSpell = 0 -- Placeholder, spellFx
local currentColor = 0 -- Placeholder, colorTable
local distanceInterval = 10 -- Distance the spell travels
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = {workspace.Detect}
local spellColors = { -- Choose a random color for the spell to add some visual variability
	["Freeze"] = {BrickColor.new("Bright blue"), BrickColor.new("Cyan"), BrickColor.new("Really blue")};
	["Bleed"] = {BrickColor.new("Bright red"), BrickColor.new("Really red"), BrickColor.new("Persimmon")};
	["Kill"] = {BrickColor.new("Black"),BrickColor.new("Dark red"),BrickColor.new("Crimson")};
	["Explode"] = {BrickColor.new("New Yeller"),BrickColor.new("Brick yellow"),BrickColor.new("Bright orange")};
	["Decapitate"] = {BrickColor.new("Hot pink"),BrickColor.new("Light pink"),BrickColor.new("Carnation pink")};
}
local fxTable = { 	-- Regular function table for casting vs changing spells, assign memory now as mini-optimization
	["castSpell"] = 0;
	["changeSpell"] = 0;
}
local attachmentTable = setmetatable({}, {__newindex = function(self, index:number, value:BasePart) -- Table to keep track of decapitated heads. __newindex to serve as a "table.added" event 
	if index == 1 then -- Our fist time adding a head via the decapitate spell, need to setup the spinner 
		local spinPart:BasePart = Instance.new("Part",workspace) spinPart.Name = player.Name.."'s Spinner" -- Create our spinner base
		spinPart.CanCollide = false
		spinPart.Transparency = 1
		spinPart.Massless = true
		spinPart.Size = Vector3.new(1,1,1)
		local weld:Weld = Instance.new("Weld",spinPart) -- Using a clasic Weld as WeldConstraint doesnt have C0 and C1
		weld.Part0 = char.HumanoidRootPart
		weld.Part1 = spinPart
		local spinCoro = coroutine.create(function()
			while true do task.wait()
				weld.C0 *= CFrame.Angles(0,math.rad(0.5),0)
			end
		end)
		char.Humanoid.Died:Once(function() -- Cleanup on death
			coroutine.close(spinCoro)
			self = nil
		end)
		coroutine.resume(spinCoro)
		rawset(self,index,spinPart) -- Allows indexing of the spinner without relying on its worldtree position in a character
		local newAttachment = Instance.new("Attachment",spinPart) -- New Attachment pareneted to spinner 
		rawset(self,index+1,newAttachment) -- Add our first attachment after the spinner index
	else
		local newAttachment = Instance.new("Attachment",self[1]) -- Attachment under spinner
		rawset(self,index,newAttachment) -- Add to the table
	end
	-- Setup attachments and constraints for the acquisition effect
	local headAttachment:Attachment = Instance.new("Attachment",value) -- Attachment in the head
	local referenceAttachemnt:Attachment = (self[index]:IsA("Attachment")) and self[index] or self[index+1] -- The attachment we just added to the table, have to account for whether self[index] is the spinner or not on first run
	local alignPosition:AlignPosition = Instance.new("AlignPosition",value)
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment -- Default but just to be safe
	alignPosition.Attachment0 = headAttachment
	alignPosition.Attachment1 = referenceAttachemnt
	alignPosition.RigidityEnabled = false -- For now
	alignPosition.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	alignPosition.MaxForce = value:GetMass() * workspace.Gravity
	alignPosition.MaxVelocity = 0 -- Make it float for the moment
	local alignOrientation:AlignOrientation = Instance.new("AlignOrientation",value)
	alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment -- Again, just to ensure
	alignOrientation.Attachment0 = headAttachment
	alignOrientation.Attachment1 = referenceAttachemnt
	alignOrientation.AlignType = Enum.AlignType.AllAxes
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxAngularVelocity = 0
	-- Set attachment offsets
	for ind:number, attachment:Attachment in pairs(self) do
		if ind == 1 then continue end -- Ignore the spinner
		attachment.CFrame = CFrame.Angles(0,math.rad( (ind-1)*(360/(#self-1)) ),0) * CFrame.new(0,0,-10)
	end
	alignPosition.MaxVelocity = math.huge
	coroutine.wrap(function()
		repeat task.wait(0.1) until (headAttachment.WorldPosition - referenceAttachemnt.WorldPosition).Magnitude < 10
		alignOrientation.RigidityEnabled = true
	end)()
end,})

--	Spell Functions
local spellTable = { 
	["Freeze"] = function(obj:Model) -- Freeze function, gets the size of the target, welds them to the ice block. Block is heavy but can move as a real ice block would
		if not obj:FindFirstChild("Humanoid") then return end
		local v0 = obj:GetExtentsSize()
		local iceBlock = Instance.new("Part",workspace)
		iceBlock.Size = v0 + Vector3.new(2,2,2)
		iceBlock.Transparency = 0.5 
		iceBlock.Material = Enum.Material.Ice -- Adjusts the the physical properties 
		iceBlock.BrickColor = BrickColor.Blue()
		local weld = Instance.new("WeldConstraint", iceBlock) 
		weld.Part0 = obj.PrimaryPart 
		weld.Part1 = iceBlock
		iceBlock.Position = obj.PrimaryPart.Position -- Last, only set Position not CFrame
		game.Debris:AddItem(iceBlock, 5)
	end;
	["Bleed"] = function(obj:Model) -- Bleed function, causes incremental decrease in health over time, TakeDamage to account for forcefields
		if not obj:FindFirstChild("Humanoid") then return end
		coroutine.wrap(function()
			for i = 1, math.random(60,120) do task.wait(0.33) -- Might kill them, might not
				obj.Humanoid:TakeDamage(1)
			end
		end)()
	end;
	["Kill"] = function(obj:Model) -- Applies infinite damage, utilizes TakeDamage to account for forcefields
		if not obj:FindFirstChild("Humanoid") then return end
		obj.Humanoid:TakeDamage(math.huge)
	end;
	["Explode"] = function(obj:Model, v1:Vector3) -- Projectile explodes on contact. Takes advantage of the .Hit event to avoid killing the caster
		local ex = Instance.new("Explosion") ex.BlastRadius = 5 ex.BlastPressure = 0 -- Settings so we can ignore our own self
		ex.Hit:Connect(function(part: BasePart, distance: number)
			if part:IsDescendantOf(player.Character) then return end
			if part.Name == "Head" then part:Destroy() end -- Kill them, I miss BreakJoints()
			part:ApplyImpulse((part.Position - ex.Position) * part.AssemblyMass * math.random(50,100)) -- Fling, Partmass * Velocity, ignore gravity
		end)
		ex.Position = v1
		ex.Parent = workspace -- Parent last for the finished product
	end,
	["Decapitate"] = function(obj:Model) -- Behead the target and keep it as a pet / trophy
		if not obj:FindFirstChild("Humanoid") or not obj:FindFirstChild("Head") then return end
		local head:BasePart = obj.Head -- Check for head
		obj.Archivable = true -- For player characters
		local newHead = obj.Head:Clone() -- Recreate the head (the existing one will despawn with the target)
		for ind:number, obj:Instance in pairs(newHead:GetChildren()) do
			if obj:IsA("Attachment") then -- Clean up the head
				obj:Destroy()
			end
		end
		newHead:PivotTo(obj.Head:GetPivot())
		for ind, accessory:Accessory in pairs(obj.Humanoid:GetAccessories()) do
			if accessory.Handle.AccessoryWeld.Part1 == obj.Head then
				local newAccessory = accessory:Clone()
				newAccessory.Parent = newHead
				newAccessory.Handle.AccessoryWeld.Part1 = newHead
				for ind2:number, obj:Instance in pairs(newAccessory.Handle:GetChildren()) do
					if not obj:IsA("Weld") then -- Clean up the attachment
						obj:Destroy()
					end
				end
			end
		end
		obj.Head:Destroy() -- Delete the head to actually kill the target
		newHead.Parent = workspace
		attachmentTable[#attachmentTable+1] = newHead -- Fires __newindex and will handle the welding
	end,
}
currentSpell = spellTable.Freeze -- Assign after the spells are defined
currentColor = spellColors["Freeze"]

fxTable.castSpell = function(player:Player, v1:Vector3) -- Cast function
	local c0:CFrame = CFrame.new(castOrigin.WorldPosition, v1)
	local projectile:BasePart = Instance.new("Part",workspace)
	projectile.Anchored = true
	projectile.Size = Vector3.one
	projectile.CFrame = c0
	projectile.Transparency = 0.5
	projectile.Color = currentColor[math.random(1,#currentColor)].Color
	projectile.Material = Enum.Material.Neon
	local specialMesh:SpecialMesh = Instance.new("SpecialMesh",projectile)
	specialMesh.MeshType = Enum.MeshType.Sphere
	specialMesh.Scale = Vector3.new(0.5,0.5,3)
	local attachment0:Attachment = Instance.new("Attachment", projectile) 
	attachment0.Position = Vector3.new(1,0,0)
	local attachment1:Attachment = attachment0:Clone() attachment1.Parent = projectile 
	attachment1.Position = Vector3.new(-1,0,0)
	local trail:Trail = Instance.new("Trail", projectile) 
	trail.Attachment0 = attachment0 
	trail.Attachment1 = attachment1 
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.MaxLength = 20
	trail.MinLength = 1
	trail.TextureLength = 1
	trail.WidthScale = NumberSequence.new(0.5,0.1) 
	trail.Transparency = NumberSequence.new(0,1)
	trail.Color = ColorSequence.new(projectile.Color)
	--trail.FaceCamera = false
	trail.LightInfluence = 0
	for i = 0, 300, distanceInterval do task.wait(0.025)
		local rayResult:RaycastResult = workspace:Raycast(c0.Position, c0.LookVector*distanceInterval, params)
		if rayResult then
			projectile.PivotOffset = CFrame.identity
			projectile:PivotTo(CFrame.new(rayResult.Position))
			currentSpell(rayResult.Instance.Parent, rayResult.Position) -- Humanoid check done in the spell function so we dont have to create a bunch of if/elseif's here
			break
		else
			c0 *= CFrame.new(0,0,-distanceInterval)
			projectile.PivotOffset = CFrame.new(math.random(-1,1),math.random(-1,1),0) * CFrame.Angles(0,0,math.rad(i*6))
			projectile:PivotTo(c0)
		end
	end
	projectile:Destroy()
end

fxTable.changeSpell = function(player:Player, newSpell:string) -- Change selected spell
	for name:string, fx in pairs(spellTable) do
		if name == newSpell then
			currentSpell = fx
			currentColor = spellColors[name]
			break
		end
	end
end

--{{ Connections }}--
remote.OnServerEvent:Connect(function(player:Player, fxName:string, ...:any)
	if fxTable[fxName] then -- Cant use variadics with pcall so we get left with an if-else check
		fxTable[fxName](player, ...)
	else
		player:Kick("Exploiting? In this economy? That's craaaaazy") 
	end
end)
