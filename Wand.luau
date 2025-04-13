-- Magic Wand Script(s), Contains both the server and local scripts (each of which is marked), but kept in one file to comply with application guidelines (my bad on that first attempt, new to github)
----------{{ SERVER SCRIPT }}----------
--// Variables \\--
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

--// Spell Functions \\--
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

fxTable.castSpell = function(player:Player, v1:Vector3) -- Projectile function
	local c0:CFrame = CFrame.new(castOrigin.WorldPosition, v1) -- Wand position
	local projectile:BasePart = Instance.new("Part",workspace) -- Projectile
	projectile.Anchored = true
	projectile.Size = Vector3.one
	projectile.CFrame = c0
	projectile.Transparency = 0.5
	projectile.Color = currentColor[math.random(1,#currentColor)].Color -- Assign a random color from the preset color tables
	projectile.Material = Enum.Material.Neon
	local specialMesh:SpecialMesh = Instance.new("SpecialMesh",projectile) -- Special mesh to make bullet appearance while still getting the Neon material effect
	specialMesh.MeshType = Enum.MeshType.Sphere
	specialMesh.Scale = Vector3.new(0.5,0.5,3)
	local attachment0:Attachment = Instance.new("Attachment", projectile) -- Attachment0 for trail effect
	attachment0.Position = Vector3.new(1,0,0)
	local attachment1:Attachment = attachment0:Clone() -- Attachment1 for trail effect
  attachment1.Parent = projectile 
	attachment1.Position = Vector3.new(-1,0,0)
	local trail:Trail = Instance.new("Trail", projectile) -- Trail effect for projectile
	trail.Attachment0 = attachment0 
	trail.Attachment1 = attachment1 
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.MaxLength = 20
	trail.MinLength = 1
	trail.TextureLength = 1
	trail.WidthScale = NumberSequence.new(0.5,0.1) 
	trail.Transparency = NumberSequence.new(0,1)
	trail.Color = ColorSequence.new(projectile.Color)
	trail.LightInfluence = 0
	for i = 0, 300, distanceInterval do task.wait(0.025) -- For loop to make the projectile move and do hit detection
		local rayResult:RaycastResult = workspace:Raycast(c0.Position, c0.LookVector*distanceInterval, params) -- Check for a hit
		if rayResult then -- Target acquired
			projectile.PivotOffset = CFrame.identity -- Remove any pivotoffset we had
			projectile:PivotTo(CFrame.new(rayResult.Position)) -- CFrame to hit position
			currentSpell(rayResult.Instance.Parent, rayResult.Position) -- Call the equipped spell. (Note: Humanoid checks are done in each  spell function so we dont have to create a bunch of if/elseif's here)
			break -- All done
		else -- Didnt hit anything
			c0 *= CFrame.new(0,0,-distanceInterval) -- Move forward by the desired distance
			projectile.PivotOffset = CFrame.new(math.random(-1,1),math.random(-1,1),0) * CFrame.Angles(0,0,math.rad(i*6)) -- Assign a pivot offset to make the spell look 'chaotic' rather than a laser beam
			projectile:PivotTo(c0) -- Update our CFrame, needs to use PivotTo to apply the PivotOffset
		end
	end
	projectile:Destroy() -- Cleanup
end

fxTable.changeSpell = function(player:Player, newSpell:string) -- Change selected spell
	for name:string, fx in pairs(spellTable) do -- Loop through spells
		if name == newSpell then -- Spell we're equipping
			currentSpell = fx -- Spell fx
			currentColor = spellColors[name] -- Color table
			break -- Early exit once we find it
		end
	end
end

--// Connections \\--
remote.OnServerEvent:Connect(function(player:Player, fxName:string, ...:any)
	if fxTable[fxName] then -- If our function exists
		fxTable[fxName](player, ...)
	else -- Tried to call a function that doesnt exist, exploit detected
		player:Kick("Exploiting? In this economy? That's craaaaazy") 
	end
end)

----------{{ LOCAL SCRIPT }}----------
--// Variables \\--
local cas = game:GetService("ContextActionService")
local player:Player = game.Players.LocalPlayer
local char:Model = player.Character or player.CharacterAdded:Wait()
local mouse:Mouse = player:GetMouse()
local plrGui:PlayerGui = player:WaitForChild("PlayerGui")
local tool:Tool = script.Parent
local handle:BasePart = tool:WaitForChild("Handle")
local remote:RemoteEvent = tool:WaitForChild("RemoteEvent")
local spellGui:ScreenGui = tool:WaitForChild("SpellGui") spellGui.Parent = plrGui
local castDebounce:boolean = false
local changeDebounce:boolean = false
local cnxTable:{} = {} -- Table that will hold our GuiButton connections
local partying = false
local colors = { -- Rainbow colors for partymode, formatted for visiblity
	BrickColor.new("Bright red"), 
	BrickColor.new("Bright orange"), 
	BrickColor.new("Bright yellow"), 
	BrickColor.new("Bright green"), 
	BrickColor.new("Bright blue"), 
	BrickColor.new("Dark indigo"), 
	BrickColor.new("Bright violet"),
}

--// Tool Functions\\--
-- Tool activated, fires the remote to the server with the mouse position as the target
local function activateTool(name:string, userInputState:Enum.UserInputState, inputObject:InputObject) 
	if userInputState ~= Enum.UserInputState.Begin then return end -- Only fire on mouse down
	if castDebounce then return end -- Debounce
	castDebounce = true
	remote:FireServer('castSpell', mouse.Hit.Position) -- Fire our remote to handle spell on server
	task.delay(1, function() castDebounce = false end) -- Cooldown
end

-- Party mode, enables disco lighting for fun (only evokes changes on client). 
local function partyMode(name:string, userInputState:Enum.UserInputState, inputOject:InputObject)
	if userInputState ~= Enum.UserInputState.Begin then return end -- Only register the keydown input
	if partying then -- Already on -> turn off
		partying = false
	else -- Otherwise turn on
		partying = true
		local colordelta = 1 -- For keeping track of when to restart the color table loop
		local lightdelta = 1 -- Whether our point light should be growing (positive) or shrinking (negative) in size
		tool.Handle.PointLight.Enabled = true
		game.Lighting.TimeOfDay = "20:00:00" -- "Ouch, squidward, I burned my hand! ... at night"
		while partying do task.wait(math.clamp(math.random(),0.5,1)) -- Wait some random inerval of time between 0.5 - 1 seconds each loop
			local color = colors[colordelta] -- Reference for the color to avoid repeat table[index]
			tool.Handle.BrickColor = color
			tool.Handle.PointLight.Color = color.Color
			tool.Handle.PointLight.Range += lightdelta -- Grow / shrink our light range to give it a 'pulsing' effect of sorts
			if tool.Handle.PointLight.Range >= 20 or tool.Handle.PointLight.Range <= 8 then -- When we reach an upper or lower limit on light size
				lightdelta *= -1 -- Flip the sign
			end
			colordelta += 1 -- Next color
			if colordelta >= #colors then -- Out of colors?
				colordelta = 1 -- Back to the start
			end
		end
    -- Partymode disabled, revert to normal settings
		tool.Handle.PointLight.Enabled = false
		tool.Handle.BrickColor = BrickColor.new("Brown")
		game.Lighting.TimeOfDay = "13:00:00"
	end
end

-- Equip tool, sets up GuiButton connections and binds our functions via ContextActionService  
local function equipTool(tool:Tool)
	-- Create a table that holds our GuiButton.MouseButton1Down connections so we can disconnect them on unequip -> Just to demo the idea of conserving memory.
	for index:number, txtBtn:TextButton in pairs(spellGui.Frame:GetChildren()) do
		if not txtBtn:IsA("TextButton") then continue end -- Ignore non-TextButtons
		table.insert(cnxTable, txtBtn.MouseButton1Down:Connect(function() -- Add our connection using table.insert as its optimized
			if changeDebounce then -- Debounce
				print('Spell change on cooldown') 
				return 
			end
			changeDebounce = true
			remote:FireServer('changeSpell', txtBtn.Name) -- Fire the remote to tell the server what spell were casting. Would be useful as an anti-cheat in a full game w/ more spells that need unlocking
			for index2:number, txtBtn2:TextButton in pairs(spellGui.Frame:GetChildren()) do -- Do another loop to Update our buttons textcolors so we can show a change in equip status
				if txtBtn == txtBtn2 then -- Textbutton we just selected
					txtBtn2.TextColor3 = BrickColor.Yellow().Color
				elseif txtBtn2:IsA("TextButton") then -- Textbuttons that we didnt select
					txtBtn2.TextColor3 = BrickColor.Black().Color
				end
			end
			task.delay(0.25, function() -- 0.25 second cooldown on spell changes
				changeDebounce = false 
			end)
		end)) -- Close table.insert 
	end
	spellGui.Enabled = true -- Turn on our spell menu
	cas:BindAction("ClickToCast", activateTool, false, Enum.UserInputType.MouseButton1) -- Enable activate-on-mouse-click
	cas:BindAction("Party",partyMode,false,Enum.KeyCode.Q) -- Enable party mode keybind
end

-- Unequip tool, unbinds our CAS functions and removes connections for the GuiButtons
local function unequipTool()
	spellGui.Enabled = false -- Hide gui
	cas:UnbindAction("ClickToCast") -- Unbind
	cas:UnbindAction("Party") partying = false -- Unbind, set to false to break the loop and revert to normal lighting
	for ind:number, cnx:RBXScriptConnection in pairs(cnxTable) do -- Remove menu gui connections
		cnx:Disconnect() -- Disconnect buttons. Another theoretical anti-cheat so you cant change spells without having the wand equipped
	end
end

--// Connections \\--
cas.LocalToolEquipped:Connect(equipTool) -- Bind equipTool
cas.LocalToolUnequipped:Connect(unequipTool) -- Bind unequipTool
