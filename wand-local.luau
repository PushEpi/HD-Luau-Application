--{{ Variables }}--
local cas = game:GetService("ContextActionService")
local player:Player = game.Players.LocalPlayer
local char:Model = player.Character or player.CharacterAdded:Wait()
local mouse:Mouse = player:GetMouse()
local plrGui:PlayerGui = player:WaitForChild("PlayerGui")
local cnxTable:{} = {}
local tool:Tool = script.Parent
local handle:BasePart = tool:WaitForChild("Handle")
local remote:RemoteEvent = tool:WaitForChild("RemoteEvent")
local spellGui:ScreenGui = tool:WaitForChild("SpellGui") spellGui.Parent = plrGui
local castDebounce:boolean = false
local changeDebounce:boolean = false
local partying = false
local colors = {BrickColor.new("Bright red"), BrickColor.new("Bright orange"), BrickColor.new("Bright yellow"), BrickColor.new("Bright green"), BrickColor.new("Bright blue"), BrickColor.new("Dark indigo"), BrickColor.new("Bright violet")}

--{{ Tool Functions }}--
local function activateTool(name:string, userInputState:Enum.UserInputState, inputObject:InputObject)
	if userInputState ~= Enum.UserInputState.Begin then return end -- Only fire on mouse down
	if castDebounce then return end
	castDebounce = true
	remote:FireServer('castSpell', mouse.Hit.Position)
	task.delay(1, function() castDebounce = false end)
end

local function partyMode(name:string, userInputState:Enum.UserInputState, inputOject:InputObject) -- Local so we can all party as we please
	if userInputState ~= Enum.UserInputState.Begin then return end -- Enable
	if partying then
		partying = false
	else
		partying = true
		local colordelta = 1
		local lightdelta = 1
		tool.Handle.PointLight.Enabled = true
		game.Lighting.TimeOfDay = "20:00:00"
		while partying do task.wait(math.clamp(math.random(),0.5,1))
			local color = colors[colordelta]
			print(color.Name)
			tool.Handle.BrickColor = color
			tool.Handle.PointLight.Color = color.Color
			tool.Handle.PointLight.Range += lightdelta
			if tool.Handle.PointLight.Range >= 20 or tool.Handle.PointLight.Range <= 8 then -- Pulses the size slowly
				lightdelta *= -1
			end
			colordelta += 1
			if colordelta >= #colors then
				colordelta = 1
			end
		end
		tool.Handle.PointLight.Enabled = false
		tool.Handle.BrickColor = BrickColor.new("Brown")
		game.Lighting.TimeOfDay = "13:00:00"
	end
end

local function equipTool(tool:Tool)
	for index:number, txtBtn:TextButton in pairs(spellGui.Frame:GetChildren()) do -- Store connections in table that we can disconnect later to prevent memory leak
		if not txtBtn:IsA("TextButton") then continue end
		cnxTable[index] = txtBtn.MouseButton1Down:Connect(function()
			if changeDebounce then 
				print('Spell change on cooldown') 
				return 
			end
			changeDebounce = true
			remote:FireServer('changeSpell', txtBtn.Name)
			for index2:number, txtBtn2:TextButton in pairs(spellGui.Frame:GetChildren()) do
				if txtBtn == txtBtn2 then -- Textbutton we just selected
					txtBtn2.TextColor3 = BrickColor.Yellow().Color
				elseif txtBtn2:IsA("TextButton") then -- Textbuttons that we didnt select
					txtBtn2.TextColor3 = BrickColor.Black().Color
				end
			end
			task.delay(0.25, function() -- 0.25 second cooldown on spell changes
				changeDebounce = false 
			end)
		end)
	end
	
	spellGui.Enabled = true
	cas:BindAction("ClickToCast", activateTool, false, Enum.UserInputType.MouseButton1)
	cas:BindAction("Party",partyMode,false,Enum.KeyCode.Q)
end

local function unequipTool()
	spellGui.Enabled = false
	cas:UnbindAction("ClickToCast")
	cas:UnbindAction("Party") partying = false
	for ind, cnx:RBXScriptConnection in pairs(cnxTable) do -- Remove menu gui connections
		if cnx.Connected then
			cnx:Disconnect()
		end
	end
end

--{{ Connections }}--
cas.LocalToolEquipped:Connect(equipTool)
cas.LocalToolUnequipped:Connect(unequipTool)
