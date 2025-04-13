-- Magic Wand Demo, Niveum, 2025
-- This file contains the code for both the server and local scripts (each of which is marked below), but are kept in one file to comply with application guidelines (my bad on that first attempt)
-- The Server Script (lines 8 - 231) is 214 lines of code when ignoring comments, blank lines, & closing bracket lines
-- The Local Script (lines 237 - 341) was included for completeness (rather than to meet line requirements).

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
params.FilterDescendantsInstances = {workspace.Detect} -- For purposes of demo, only detect items in the designated folder
local spellColors = { -- Choose a random color for the spell to add some visual variability
	["Freeze"] = {BrickColor.new("Bright blue"), BrickColor.new("Cyan"), BrickColor.new("Really blue")};
	["Bleed"] = {BrickColor.new("Bright red"), BrickColor.new("Really red"), BrickColor.new("Persimmon")};
	["Kill"] = {BrickColor.new("Black"),BrickColor.new("Dark red"),BrickColor.new("Crimson")};
	["Explode"] = {BrickColor.new("New Yeller"),BrickColor.new("Brick yellow"),BrickColor.new("Bright orange")};
	["Decapitate"] = {BrickColor.new("Hot pink"),BrickColor.new("Light pink"),BrickColor.new("Carnation pink")};
}
local fxTable = { -- Table that will hold casting & changing functions to use in conjunction with wrapper function that handles remote events. Defined here w/ variables to allocate memory early as a micro-optimization
	["castSpell"] = 0;
	["changeSpell"] = 0;
}
local attachmentTable = setmetatable({}, {__newindex = function(self, index:number, value:BasePart) -- Table to keep track of decapitation attachments,  __newindex to serve as a "table.added" event to utilize metamethods in demo, and also easier on script organization
	if index == 1 then -- Our fist time adding an attachment via the decapitate spell, need to setup the spinner 
		local spinPart:BasePart = Instance.new("Part",workspace) spinPart.Name = player.Name.."'s Spinner" -- Create spinner part
		spinPart.CanCollide = false
		spinPart.Transparency = 1
		spinPart.Massless = true
		spinPart.Size = Vector3.new(1,1,1)
		local weld:Weld = Instance.new("Weld",spinPart) -- Weld to character
		weld.Part0 = char.HumanoidRootPart
		weld.Part1 = spinPart
		local spinCoro = coroutine.create(function() -- Create coroutine
			while true do task.wait()
				weld.C0 *= CFrame.Angles(0,math.rad(0.5),0)
			end
		end)
		char.Humanoid.Died:Once(function() -- Player dies
			coroutine.close(spinCoro) -- Close out our coroutine
			self = nil -- Remove attachment table
		end)
		coroutine.resume(spinCoro) -- Start coroutine
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
	local alignPosition:AlignPosition = Instance.new("AlignPosition",value) -- Using align position rather than a weld as it creates a 'float' effect. 
	alignPosition.Mode = Enum.PositionAlignmentMode.TwoAttachment -- Default but just to be safe
	alignPosition.Attachment0 = headAttachment
	alignPosition.Attachment1 = referenceAttachemnt
	alignPosition.RigidityEnabled = false
	alignPosition.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	alignPosition.MaxForce = value:GetMass() * workspace.Gravity
	alignPosition.MaxVelocity = 0 -- Start by floating
	local alignOrientation:AlignOrientation = Instance.new("AlignOrientation",value)
	alignOrientation.Mode = Enum.OrientationAlignmentMode.TwoAttachment -- Again, just to ensure
	alignOrientation.Attachment0 = headAttachment
	alignOrientation.Attachment1 = referenceAttachemnt
	alignOrientation.AlignType = Enum.AlignType.PrimaryAxisLookAt -- Looks at its target attachemnt as it floats towards it, makes it look like it knows where it going
	alignOrientation.RigidityEnabled = false
	alignOrientation.MaxAngularVelocity = 0
	-- Update attachment offsets
	local numAttachments:number = (#self)-1 -- Reference to avoid repeat calls of '#self'
	for ind:number, attachment:Attachment in pairs(self) do
		if ind == 1 then continue end -- Ignore the spinner
		attachment.CFrame = CFrame.Angles(0, math.rad((ind-1)*(360/(numAttachments))), 0) * CFrame.new(0, 0, -6 - numAttachments) -- Equally divide into circle, and space outwards as we add more heads
	end
	alignPosition.MaxVelocity = math.huge -- Move as fast MaxForce can allow for
	coroutine.wrap(function() -- Coroutine to make a new thread because __newindex cant/shouldnt yield, but its needed for the effect to look right 
		repeat task.wait(0.1) until (headAttachment.WorldPosition - referenceAttachemnt.WorldPosition).Magnitude < 10 -- Wait until we get close
		alignOrientation.AlignType = Enum.AlignType.AllAxes -- Causes the head to twist into place
		alignOrientation.RigidityEnabled = true -- Stay as alinged as possible now
	end)()
end,})

--// Spell Functions \\--
local spellTable = { 
	["Freeze"] = function(obj:Model) -- Freeze function, gets the size of the target, creates ice block of larger size, welds iceblock to target.
		if not obj:FindFirstChild("Humanoid") then return end
		local v0 = obj:GetExtentsSize()
		local iceBlock = Instance.new("Part",workspace)
		iceBlock.Size = v0 + Vector3.new(2,2,2)
		iceBlock.Transparency = 0.5 
		iceBlock.Material = Enum.Material.Ice -- Bonus of applying the physical properties of ice 
		iceBlock.BrickColor = BrickColor.Blue()
		local weld = Instance.new("WeldConstraint", iceBlock) 
		weld.Part0 = obj.PrimaryPart 
		weld.Part1 = iceBlock
		iceBlock.Position = obj.PrimaryPart.Position -- Set position to update only the iceblocks offset
		game.Debris:AddItem(iceBlock, 5) -- Cleanup after 5 seconds
	end;
	["Bleed"] = function(obj:Model) -- Bleed function, causes incremental decrease in health over time,
		if not obj:FindFirstChild("Humanoid") then return end
		local bleedCoro = coroutine.create(function()
			for i = 1, math.random(60,120) do task.wait(0.33) -- Might kill them, might not
				obj.Humanoid:TakeDamage(1)
			end
		end)
		obj.Humanoid.Died:Once(function() -- Early exit's the for loop + avoids the 'humanoid not found' error when they respawn
			coroutine.close(bleedCoro)
		end)
		coroutine.resume(bleedCoro)
	end;
	["Kill"] = function(obj:Model) -- Applies infinite damage, utilizes TakeDamage to account for forcefields
		if not obj:FindFirstChild("Humanoid") then return end
		obj.Humanoid:TakeDamage(math.huge)
	end;
	["Explode"] = function(obj:Model, v1:Vector3) -- Projectile which explodes on contact, 
		local explosion:Explosion = Instance.new("Explosion") 
		explosion.BlastRadius = 15 
		explosion.BlastPressure = 0
		explosion.Hit:Connect(function(part: BasePart, distance: number) -- Uses hit to avoid killin the caster 
			if part:IsDescendantOf(player.Character) then return end -- Ignore caster 
			if part.Parent:FindFirstChild("Humanoid") then 
				part.Parent.Humanoid:TakeDamage(math.huge) -- Explosions 1 shot for now
			end
			if part:HasTag("Destroyable") then -- For the destroyable brick wall in the demo game as part of its self-repairing feature
				part.Anchored = false
			end
			part:ApplyImpulse(part.AssemblyMass * ((part.Position - explosion.Position).Unit * math.random(50,100))) -- Fling = Partmass * VelocityVector, ignore gravity so parts can come down
		end)
		explosion.Position = v1
		explosion.Parent = workspace -- Parent last for the finished product
	end,
	["Decapitate"] = function(obj:Model) -- Behead the target and keep it as a pet / trophy
		if not obj:FindFirstChild("Humanoid") or not obj:FindFirstChild("Head") then return end
		local head:BasePart = obj.Head -- Check for head
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
currentSpell = spellTable.Freeze -- Assign function now that its defined
currentColor = spellColors["Freeze"] -- Keep color consistent with equipped spell

fxTable.castSpell = function(player:Player, v1:Vector3) -- Cast function
	local c0:CFrame = CFrame.new(castOrigin.WorldPosition, v1) -- Wand position in global space
	local projectile:BasePart = Instance.new("Part",workspace) -- Spell projectile
	projectile.Anchored = true
	projectile.Size = Vector3.one
	projectile.CFrame = c0
	projectile.Transparency = 0.5
	projectile.Color = currentColor[math.random(1,#currentColor)].Color
	projectile.Material = Enum.Material.Neon
	local specialMesh:SpecialMesh = Instance.new("SpecialMesh",projectile) -- Use Special mesh to make it more bullet-shaped while still rendering as the Neon material (Shape seems to have issues with this)
	specialMesh.MeshType = Enum.MeshType.Sphere
	specialMesh.Scale = Vector3.new(0.5,0.5,3)
	local attachment0:Attachment = Instance.new("Attachment", projectile) -- Attachment 0 for the trail effect
	attachment0.Position = Vector3.new(1,0,-1)
	local attachment1:Attachment = attachment0:Clone() -- Attachment 1 for trail effect
	attachment1.Parent = projectile 
	attachment1.Position = Vector3.new(-1,0,-1)
	local trail:Trail = Instance.new("Trail", projectile) -- Trail effect
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
	for i = 0, 300, distanceInterval do task.wait(0.025) -- For loop which moves the projectile along its path
		local rayResult:RaycastResult = workspace:Raycast(c0.Position, c0.LookVector*distanceInterval, params) -- Hit detection
		if rayResult then -- Target acquired
			projectile.PivotOffset = CFrame.identity -- Remove any existing pivot offset used for the chaotic path effect
			projectile:PivotTo(CFrame.new(rayResult.Position)) -- Pivot to target
			currentSpell(rayResult.Instance.Parent, rayResult.Position) -- Call our current spell (Humanoid check is done in the spell function as not all spells will need to hit a player  to activate, such  as explode)
			break -- All done
		else -- Keep movin'
			c0 *= CFrame.new(0,0,-distanceInterval) -- Update our reference CFrame for the next loop
			projectile.PivotOffset = CFrame.new(math.random(-1,1),math.random(-1,1),0) * CFrame.Angles(0,0,math.rad(i*3)) -- Apply a pivotOffset to create a 'chaotic' path effect rather than it being a laser
			projectile:PivotTo(c0) -- Have to use PivotTo in order to apply the PivotOffset
		end
	end
	projectile:Destroy() -- Cleanup
end

fxTable.changeSpell = function(player:Player, newSpell:string) -- Change selected spell
	for name:string, fx in pairs(spellTable) do
		if name == newSpell then -- Found the spell we're tring to select
			currentSpell = fx -- set it as the equipped spell
			currentColor = spellColors[name] -- update our projectile colors
			break -- early exit
		end
	end
end

--// Connections \\--
remote.OnServerEvent:Connect(function(player:Player, fxName:string, ...:any)
	if fxTable[fxName] then -- Cant use variadics with pcall so we get left with an if-else check
		fxTable[fxName](player, ...)
	else -- Tried to call a function that doesn't exist, exploit detected
		player:Kick("Exploiting? In this economy? Wack") 
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
local colors = { -- Rainbow colors for partymode, formatted for visiblity rather than line requirement
	BrickColor.new("Bright red"), 
	BrickColor.new("Bright orange"), 
	BrickColor.new("Bright yellow"), 
	BrickColor.new("Bright green"), 
	BrickColor.new("Bright blue"), 
	BrickColor.new("Dark indigo"), 
	BrickColor.new("Bright violet"),
}

--// Tool Functions \\--

-- Tool activated, fires the remote to the server with the mouse position for aiming
local function activateTool(name:string, userInputState:Enum.UserInputState, inputObject:InputObject) 
	if userInputState ~= Enum.UserInputState.Begin then return end -- Only fire on mouse down
	if castDebounce then return end -- Debounce
	castDebounce = true
	remote:FireServer('castSpell', mouse.Hit.Position) -- Fire our remote to handle spell on server
	task.delay(1, function() castDebounce = false end) -- Cooldown
end

-- Party mode, enables disco lighting for fun (local effect). 
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
				lightdelta *= -1 -- Flip the sign to switch grow <--> shrink
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
			if changeDebounce then -- Debounce to avoid normal players from spamming remote:FireServer()
				print('Spell change on cooldown') -- Local so may as well let the client see why they cant spam change if they open the dev console
				return 
			end
			changeDebounce = true
			remote:FireServer('changeSpell', txtBtn.Name) -- Fire the remote to tell the server what spell to equip. Theoretically useful as an anti-cheat in a full game with more spells that need unlocking vs letting the client keep track
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
	spellGui.Enabled = true -- Make our spell menu visible
	cas:BindAction("ClickToCast", activateTool, false, Enum.UserInputType.MouseButton1) -- Enable activate-on-mouse-click
	cas:BindAction("Party",partyMode,false,Enum.KeyCode.Q) -- Enable party-mode-keybind
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
