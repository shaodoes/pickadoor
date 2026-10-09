-- Data-driven dialogue box with choices, in the Librarian's visual language: a sheet of cream paper
-- with a coloured name tab, a typewritten serif body, progress pips + NEXT / SKIP for linear runs and
-- numbered choice buttons for branching ones. One box per client, built on first use (ScreenGui
-- "DialogueUI"), always parked just above the HUD's bottom menu.
--
--   Dialogue.start(tree, opts)            run a tree (types below); takes over any open conversation
--   Dialogue.say(speaker, text, accent?)  one-line interjection: uses the box when idle, or a small
--                                         bubble above the box while a conversation is running
--   Dialogue.isOpen() / Dialogue.close()
--   Dialogue.Closed                       RBXScriptSignal, fires whenever a conversation ends
--
-- Keys: E / Space / Return (and gamepad A) advance linear nodes - the first press finishes the typing;
-- 1-4 pick choices; clicking the sheet advances linear nodes only. Walking more than 30 studs from
-- opts.anchor closes the box.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Sfx = require(script.Parent.Sfx)
local UIKit = require(script.Parent.UIKit)

local Colors, Face = UIKit.Colors, UIKit.Face

export type Choice = {
	text: string,
	next: string?, -- node to go to; nil closes the box after `action`
	action: string?, -- fired through opts.onAction when chosen (before moving on)
	when: ((ctx: any) -> boolean)?, -- hide the choice when this returns false
}
export type Node = {
	text: string | (ctx: any) -> string,
	speaker: string?, -- overrides the tree's speaker for this node
	voice: Sfx.Voice?, -- overrides the tree's voice for this node
	next: string?, -- linear continuation (NEXT button); nil + no choices = CLOSE ends it
	choices: { Choice }?, -- buttons; a choice with no `next` closes the box after its `action`
	action: string?, -- fired through opts.onAction when the node is shown
}
export type Tree = {
	speaker: string,
	accent: Color3?,
	voice: Sfx.Voice?, -- per-syllable vocal sounds while the text types (nil = the typewriter key)
	start: string | (ctx: any) -> string,
	nodes: { [string]: Node },
}
export type Options = {
	context: any?,
	onAction: ((action: string, ctx: any) -> ())?,
	onClose: (() -> ())?,
	anchor: BasePart?,
}

local Dialogue = {}

------------------------------------------------------------------------------------------
-- Layout (design pixels at 1280x720; UIKit.fit scales the whole box)
------------------------------------------------------------------------------------------
local BOX_W = 760
local LINEAR_H = 176 -- body + pips + NEXT / SKIP, the Librarian's original box
local SAY_MIN_H = 96 -- an interjection is just the line
local BODY_TOP = 30 -- the name tab hangs over the top edge, the text starts below it
local BODY_TEXT = 21
local LINE_HEIGHT = 1.15
local CHOICE_H = 46
local CHOICE_GAP = 8
local CHOICE_TOP_GAP = 12
local BOTTOM_PAD = 20
local MENU_H = 140 -- the HUD's bottom menu (Main.client) - the box never overlaps it
local MENU_GAP = 30
local CHARS_PER_SECOND = 45
local PUNCTUATION_PAUSE = 0.18
local PUNCTUATION = { ["."] = true, [","] = true, ["?"] = true, ["!"] = true }
local WALK_AWAY = 30
local SAY_HOLD = 3 -- seconds an interjection lingers once typed
local INPUT_GRACE = 0.15 -- ignore the key press that opened the box

local POP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SHUT = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local QUICK = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SERIF_ITALIC =
	Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)

local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
	[Enum.KeyCode.KeypadFour] = 4,
}
local ADVANCE_KEYS = {
	[Enum.KeyCode.E] = true,
	[Enum.KeyCode.Space] = true,
	[Enum.KeyCode.Return] = true,
	[Enum.KeyCode.ButtonA] = true,
}

------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------
type UI = {
	gui: ScreenGui,
	box: TextButton,
	fit: UIScale,
	sheet: Frame,
	tab: TextLabel,
	tabStroke: UIStroke,
	body: TextLabel,
	pips: Frame,
	nextButton: TextButton,
	skipButton: TextButton,
	choices: Frame,
	grid: UIGridLayout,
}

local ui: UI? = nil
local guiParent: Instance? = nil -- test hook (Edit mode has no LocalPlayer)
local guiName = "DialogueUI"
local closedEvent = Instance.new("BindableEvent")
Dialogue.Closed = closedEvent.Event

local state = {
	open = false,
	mode = "idle", -- "tree" | "say"
	silent = false, -- preview: no sounds, no tweens, everything at its final value
	tree = nil :: Tree?,
	opts = {} :: Options,
	ctx = nil :: any,
	accent = Colors.accent,
	nodeId = nil :: string?,
	node = nil :: Node?,
	visible = {} :: { Choice }, -- the current node's choices after `when` filtering
	cells = {} :: { Frame },
	choiceButtons = {} :: { TextButton },
	choicesShown = false,
	typing = false,
	voice = nil :: Sfx.Voice?, -- the current line's voice; nil = typewriter clicks
	typeToken = 0,
	onTyped = nil :: (() -> ())?,
	chainIndex = {} :: { [string]: number }, -- node id -> pip index for linear runs
	pipFrames = {} :: { Frame },
	heartbeat = nil :: RBXScriptConnection?,
	openedAt = 0,
	sayToken = 0,
}

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local function tween(inst: Instance, info: TweenInfo, goal: { [string]: any })
	if state.silent then
		for key, value in goal do
			(inst :: any)[key] = value
		end
		return nil
	end
	return UIKit.tween(inst, info, goal)
end

local function play(name: string, jitter: number?)
	if not state.silent then
		Sfx.play(name, jitter)
	end
end

local function speak(voice: Sfx.Voice)
	if not state.silent then
		Sfx.speak(voice)
	end
end

local function bottomPosition(): UDim2
	return UDim2.new(0.5, 0, 1, -(MENU_H * UIKit.fitScale() + MENU_GAP))
end

local function resolveText(text: string | (ctx: any) -> string, ctx: any): string
	if type(text) == "function" then
		return tostring(text(ctx))
	end
	return tostring(text)
end

local function resolveStart(tree: Tree, ctx: any): string
	if type(tree.start) == "function" then
		return tostring(tree.start(ctx))
	end
	return tostring(tree.start)
end

-- Height the body text needs at the box's width (so choice / say layouts hug their line).
local function measureBody(text: string): number
	local bounds = TextService:GetTextSize(text, BODY_TEXT, Enum.Font.Merriweather, Vector2.new(BOX_W - 52, 1000))
	return math.clamp(math.ceil(bounds.Y * LINE_HEIGHT) + 6, 30, 120)
end

-- Node ids reachable from `startId` by `next` alone; nil as soon as a node branches (or loops).
local function linearChain(tree: Tree, startId: string): { string }?
	local order, seen = {}, {}
	local id: string? = startId
	while id do
		local node = tree.nodes[id]
		if not node or seen[id] or (node.choices and #node.choices > 0) then
			return nil
		end
		seen[id] = true
		table.insert(order, id)
		id = node.next
	end
	return order
end

------------------------------------------------------------------------------------------
-- Building the box
------------------------------------------------------------------------------------------
local advance, finish, choose, finishTyping

local function ensureUI(): UI
	if ui then
		return ui
	end
	local parent = guiParent
	if not parent then
		local player = Players.LocalPlayer
		parent = if player then player:WaitForChild("PlayerGui") else StarterGui
	end
	local gui = UIKit.new("ScreenGui", {
		Name = guiName,
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})
	-- the whole box is a button (click anywhere to continue a linear line)
	local box = UIKit.new("TextButton", {
		Name = "Dialogue",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = bottomPosition(),
		Size = UDim2.fromOffset(BOX_W, LINEAR_H),
		Visible = false,
		Parent = gui,
	})
	local fit = UIKit.fit(box)
	UIKit.FitChanged:Connect(function()
		box.Position = bottomPosition()
	end)
	UIKit.shadow(box, 16, 8, 1)
	local sheet = UIKit.new("Frame", {
		Name = "Sheet",
		BackgroundColor3 = Colors.paper,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = box,
	}, { UIKit.corner(16), UIKit.stroke(Colors.ink, 2, 0.35), UIKit.sheen(0.35) })
	-- name tab hanging over the top edge
	local tabStroke = UIKit.stroke(Colors.accentDark, 1.5, 0.3)
	local tab = UIKit.new("TextLabel", {
		Name = "Speaker",
		Text = "",
		FontFace = Face.bold,
		TextSize = 18,
		TextColor3 = Colors.paperLight,
		BackgroundColor3 = Colors.accent,
		Position = UDim2.fromOffset(22, -16),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		ZIndex = 3,
		Parent = sheet,
	}, {
		UIKit.corner(8),
		tabStroke,
		UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	})
	local body = UIKit.new("TextLabel", {
		Name = "Body",
		Text = "",
		BackgroundTransparency = 1,
		FontFace = Face.serif,
		TextSize = BODY_TEXT,
		LineHeight = LINE_HEIGHT,
		TextColor3 = Colors.ink,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(26, BODY_TOP),
		Size = UDim2.new(1, -52, 1, -86),
		Parent = sheet,
	})
	-- one pip per line of a linear run; the current one is accent-coloured and wider
	local pips = UIKit.new("Frame", {
		Name = "Progress",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 26, 1, -32),
		Size = UDim2.fromOffset(260, 10),
		Parent = sheet,
	}, {
		UIKit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local nextButton = UIKit.button("NEXT", {
		Name = "Next",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -18, 1, -14),
		Size = UDim2.fromOffset(118, 40),
		ZIndex = 2,
		Parent = sheet,
	}, { style = "ink", icon = "play", iconSize = 14 })
	local skipButton = UIKit.button("SKIP", {
		Name = "Skip",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -148, 1, -14),
		Size = UDim2.fromOffset(92, 40),
		ZIndex = 2,
		Parent = sheet,
	}, { style = "paper" })
	-- numbered choice buttons, laid out in up to two columns beneath the line
	local grid = UIKit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -CHOICE_GAP / 2, 0, CHOICE_H),
		CellPadding = UDim2.fromOffset(CHOICE_GAP, CHOICE_GAP),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 2,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local choices = UIKit.new("Frame", {
		Name = "Choices",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(26, BODY_TOP),
		Size = UDim2.new(1, -52, 0, 0),
		Visible = false,
		ZIndex = 2,
		Parent = sheet,
	}, { grid })

	box.Activated:Connect(function()
		if not state.open then
			return
		end
		if state.typing then
			finishTyping()
		elseif state.mode == "say" then
			finish()
		elseif #state.visible == 0 then
			advance()
		end
	end)
	nextButton.Activated:Connect(function()
		advance()
	end)
	skipButton.Activated:Connect(function()
		finish() -- (not Connect(finish): Activated's InputObject would read as `silently`)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not state.open or processed or os.clock() - state.openedAt < INPUT_GRACE then
			return
		end
		if ADVANCE_KEYS[input.KeyCode] then
			advance()
		elseif state.choicesShown then
			local index = NUMBER_KEYS[input.KeyCode]
			if index then
				choose(index)
			end
		end
	end)

	ui = {
		gui = gui,
		box = box,
		fit = fit,
		sheet = sheet,
		tab = tab,
		tabStroke = tabStroke,
		body = body,
		pips = pips,
		nextButton = nextButton,
		skipButton = skipButton,
		choices = choices,
		grid = grid,
	}
	return ui :: UI
end

local function applyAccent(color: Color3)
	local u = ensureUI()
	state.accent = color
	u.tab.BackgroundColor3 = color
	u.tabStroke.Color = color:Lerp(Color3.new(), 0.3)
end

-- A choice button: paper face with an ink number badge and the player's line in italic serif.
local function makeChoice(index: number, choice: Choice, parent: Instance): (Frame, TextButton)
	local cell = UIKit.new("Frame", {
		Name = "Choice" .. index,
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = parent,
	}, { UIKit.new("UIScale") })
	local button = UIKit.button("", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		Parent = cell,
	}, { style = "paper", radius = 10, depth = 2 })
	local face = button:FindFirstChild("Face") :: Frame
	local badge = UIKit.new("TextLabel", {
		Name = "Number",
		Text = tostring(index) .. ".",
		FontFace = Face.bold,
		TextSize = 15,
		TextColor3 = Colors.paperLight,
		BackgroundColor3 = Colors.ink,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(28, 26),
		ZIndex = 2,
		Parent = face,
	}, { UIKit.corner(7) })
	UIKit.new("TextLabel", {
		Name = "Label",
		Text = choice.text,
		FontFace = SERIF_ITALIC,
		TextSize = 19,
		TextColor3 = Colors.ink,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -58, 1, 0),
		ZIndex = 2,
		Parent = face,
	})
	-- the badge takes the speaker's colour under the mouse
	button.MouseEnter:Connect(function()
		tween(badge, QUICK, { BackgroundColor3 = state.accent })
	end)
	button.MouseLeave:Connect(function()
		tween(badge, QUICK, { BackgroundColor3 = Colors.ink })
	end)
	button.Activated:Connect(function()
		choose(index)
	end)
	return cell, button
end

local function clearChoices()
	for _, cell in state.cells do
		cell:Destroy()
	end
	state.cells = {}
	state.choiceButtons = {}
	state.choicesShown = false
	if ui then
		ui.choices.Visible = false
	end
end

local function buildPips(count: number)
	local u = ensureUI()
	for _, pip in state.pipFrames do
		pip:Destroy()
	end
	state.pipFrames = {}
	for i = 1, count do
		state.pipFrames[i] = UIKit.new("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = Colors.paperDark,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(8, 8),
			Parent = u.pips,
		}, { UIKit.corner(4) })
	end
	u.pips.Visible = count > 0
end

local function setProgress(index: number?)
	for i, pip in state.pipFrames do
		local current = i == index
		tween(pip, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {
			Size = UDim2.fromOffset(current and 22 or 8, 8),
			BackgroundColor3 = current and state.accent
				or (index and i < index) and Colors.inkMuted
				or Colors.paperDark,
		})
	end
end

-- Size the box for the node being shown: the classic three-row layout for linear lines, a line
-- hugging its text for interjections, or line + choice grid. The box is anchored at its bottom,
-- so it grows upward.
local function setLayout(kind: string, text: string, choiceCount: number)
	local u = ensureUI()
	local controls = kind == "linear"
	u.nextButton.Visible = controls
	u.skipButton.Visible = controls
	u.pips.Visible = controls and #state.pipFrames > 0
	local height = LINEAR_H
	if kind == "linear" then
		u.body.Size = UDim2.new(1, -52, 1, -86)
	elseif kind == "say" then
		local bodyH = measureBody(text)
		u.body.Size = UDim2.new(1, -52, 0, bodyH)
		height = math.max(SAY_MIN_H, BODY_TOP + bodyH + BOTTOM_PAD)
	else
		local bodyH = measureBody(text)
		local columns = math.min(choiceCount, 2)
		local rows = math.ceil(choiceCount / columns)
		u.grid.FillDirectionMaxCells = columns
		u.grid.CellSize = if columns == 2
			then UDim2.new(0.5, -CHOICE_GAP / 2, 0, CHOICE_H)
			else UDim2.new(1, 0, 0, CHOICE_H)
		local gridH = rows * CHOICE_H + (rows - 1) * CHOICE_GAP
		u.body.Size = UDim2.new(1, -52, 0, bodyH)
		u.choices.Position = UDim2.fromOffset(26, BODY_TOP + bodyH + CHOICE_TOP_GAP)
		u.choices.Size = UDim2.new(1, -52, 0, gridH)
		height = BODY_TOP + bodyH + CHOICE_TOP_GAP + gridH + BOTTOM_PAD
	end
	tween(u.box, QUICK, { Size = UDim2.fromOffset(BOX_W, height) })
end

------------------------------------------------------------------------------------------
-- Typing
------------------------------------------------------------------------------------------
local function typeLine(text: string, onDone: (() -> ())?)
	local u = ensureUI()
	u.body.Text = text
	state.typeToken += 1
	local token = state.typeToken
	state.onTyped = onDone
	if state.silent then
		u.body.MaxVisibleGraphemes = -1
		state.typing = false
		state.onTyped = nil
		if onDone then
			onDone()
		end
		return
	end
	u.body.MaxVisibleGraphemes = 0
	state.typing = true
	local voice = state.voice
	task.spawn(function()
		local shown = 0
		local letters = 0 -- letters since the last syllable; 0 = at the start of a word
		local lastSyllable = -math.huge
		for first, last in utf8.graphemes(text) do
			if token ~= state.typeToken then
				return
			end
			shown += 1
			u.body.MaxVisibleGraphemes = shown
			local ch = text:sub(first, last)
			if voice then
				-- a syllable at the start of each word and every few letters in it; spaces and
				-- punctuation are silent
				if ch:match("^[%w']") then
					local now = os.clock()
					if
						(letters == 0 or letters >= (voice.every or 3))
						and now - lastSyllable >= (voice.gap or 0.08)
					then
						speak(voice)
						lastSyllable = now
						letters = 1
					else
						letters += 1
					end
				else
					letters = 0
				end
			elseif shown % 3 == 1 and ch ~= " " then
				play("Type", 0.15)
			end
			-- linger on punctuation like someone thinking
			task.wait(PUNCTUATION[ch] and PUNCTUATION_PAUSE or 1 / CHARS_PER_SECOND)
		end
		if token == state.typeToken then
			finishTyping()
		end
	end)
end

function finishTyping()
	if not ui then
		return
	end
	state.typeToken += 1
	ui.body.MaxVisibleGraphemes = -1
	state.typing = false
	local done = state.onTyped
	state.onTyped = nil
	if done then
		done()
	end
end

------------------------------------------------------------------------------------------
-- Open / close
------------------------------------------------------------------------------------------
local function openBox()
	local u = ensureUI()
	state.openedAt = os.clock()
	u.box.Visible = true
	if state.silent then
		u.fit.Scale = UIKit.fitScale()
		u.sheet.Position = UDim2.new()
		return
	end
	u.fit.Scale = UIKit.fitScale() * 0.9
	tween(u.fit, POP, { Scale = UIKit.fitScale() })
	u.sheet.Position = UDim2.fromOffset(0, 24)
	tween(u.sheet, POP, { Position = UDim2.new() })
	play("PanelOpen", 0.04)
end

local function hideBox()
	local u = ensureUI()
	if state.silent then
		u.box.Visible = false
		return
	end
	play("PanelClose", 0.04)
	local t = tween(u.fit, SHUT, { Scale = UIKit.fitScale() * 0.9 })
	if t then
		t.Completed:Connect(function()
			if not state.open then
				u.box.Visible = false
				u.fit.Scale = UIKit.fitScale()
			end
		end)
	end
end

local function stopWatching()
	if state.heartbeat then
		state.heartbeat:Disconnect()
		state.heartbeat = nil
	end
end

-- walking away ends the conversation
local function watchAnchor(anchor: BasePart?)
	stopWatching()
	local player = Players.LocalPlayer
	if not anchor or not player then
		return
	end
	state.heartbeat = RunService.Heartbeat:Connect(function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and anchor.Parent and (root.Position - anchor.Position).Magnitude > WALK_AWAY then
			finish()
		end
	end)
end

local function releaseSelection()
	local selected = GuiService.SelectedObject
	if selected and ui and selected:IsDescendantOf(ui.box) then
		GuiService.SelectedObject = nil
	end
end

-- `silently` skips the sound and animation (another conversation is taking the box over right away).
function finish(silently: boolean?)
	if not state.open then
		return
	end
	local wasTree = state.mode == "tree"
	local opts = state.opts
	state.open = false
	state.mode = "idle"
	state.typeToken += 1
	state.typing = false
	state.onTyped = nil
	state.choicesShown = false
	stopWatching()
	releaseSelection()
	if not silently then
		hideBox()
	end
	if wasTree then
		if opts.onClose then
			task.spawn(opts.onClose)
		end
		closedEvent:Fire()
	end
end

------------------------------------------------------------------------------------------
-- Running a tree
------------------------------------------------------------------------------------------
local showNode

local function revealChoices()
	if not state.open or state.mode ~= "tree" or #state.visible == 0 then
		return
	end
	local u = ensureUI()
	state.choicesShown = true
	u.choices.Visible = true
	for i, cell in state.cells do
		local scale = cell:FindFirstChildOfClass("UIScale") :: UIScale
		if state.silent then
			scale.Scale = 1
		else
			scale.Scale = 0.85
			task.delay((i - 1) * 0.05, tween, scale, POP, { Scale = 1 })
		end
	end
	-- gamepad players get the first choice pre-selected so A / D-pad work right away
	local lastInput = UserInputService:GetLastInputType().Name
	if string.find(lastInput, "Gamepad") and state.choiceButtons[1] then
		GuiService.SelectedObject = state.choiceButtons[1]
	end
end

function choose(index: number)
	if not state.open or state.mode ~= "tree" or not state.choicesShown then
		return
	end
	local choice = state.visible[index]
	if not choice then
		return
	end
	local opts, ctx = state.opts, state.ctx
	if choice.action and opts.onAction then
		task.spawn(opts.onAction, choice.action, ctx)
	end
	if choice.next then
		showNode(choice.next)
	else
		finish()
	end
end

function showNode(id: string)
	local u = ensureUI()
	local tree = state.tree :: Tree
	local node = tree.nodes[id]
	if not node then
		warn(string.format("[Dialogue] %s has no node %q", tree.speaker, id))
		finish()
		return
	end
	state.nodeId, state.node = id, node
	local ctx = state.ctx
	local text = resolveText(node.text, ctx)
	u.tab.Text = node.speaker or tree.speaker
	state.voice = node.voice or tree.voice

	local visible = {}
	for _, choice in node.choices or {} do
		if choice.when == nil or choice.when(ctx) then
			table.insert(visible, choice)
		end
	end
	state.visible = visible
	releaseSelection()
	clearChoices()

	if #visible > 0 then
		setLayout("choices", text, #visible)
		for i, choice in visible do
			local cell, button = makeChoice(i, choice, u.choices)
			state.cells[i] = cell
			state.choiceButtons[i] = button
		end
	else
		setLayout("linear", text, 0)
		u.nextButton.Text = node.next and "NEXT" or "CLOSE"
		setProgress(state.chainIndex[id])
	end

	if node.action and state.opts.onAction then
		task.spawn(state.opts.onAction, node.action, ctx)
	end
	typeLine(text, revealChoices)
end

function advance()
	if not state.open then
		return
	end
	if state.typing then
		-- first press finishes the line, the next one moves on
		finishTyping()
		return
	end
	if state.mode == "say" then
		finish()
		return
	end
	if #state.visible > 0 then
		return -- a choice decides where this goes
	end
	local node = state.node
	if node and node.next then
		showNode(node.next)
	else
		finish()
	end
end

local function beginTree(tree: Tree, options: Options?, nodeId: string?)
	ensureUI()
	if state.open then
		finish(true)
	end
	local opts: Options = options or {}
	local ctx = opts.context or {}
	state.mode = "tree"
	state.tree = tree
	state.opts = opts
	state.ctx = ctx
	state.open = true
	local startId = resolveStart(tree, ctx)
	-- progress pips only make sense for a straight run of lines
	state.chainIndex = {}
	local chain = linearChain(tree, startId)
	for i, id in chain or {} do
		state.chainIndex[id] = i
	end
	buildPips(chain and #chain or 0)
	applyAccent(tree.accent or Colors.accent)
	openBox()
	watchAnchor(opts.anchor)
	showNode(nodeId or startId)
end

------------------------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------------------------
function Dialogue.start(tree: Tree, options: Options?)
	state.silent = false
	beginTree(tree, options)
end

function Dialogue.isOpen(): boolean
	return state.open
end

function Dialogue.close()
	finish()
end

-- An ink bubble floating above the open box (an interjection that mustn't lose the conversation's
-- place). Sized by measuring the text: the line wraps at BUBBLE_MAX_W.
local BUBBLE_MAX_W = 480
local BUBBLE_SPEAKER, BUBBLE_LINE = 14, 18
local function showBubble(speaker: string, text: string, color: Color3, linger: number)
	local u = ensureUI()
	local old = u.box:FindFirstChild("Bubble")
	if old then
		old:Destroy()
	end
	local padL, padR, padT, padB = 22, 16, 7, 9
	local speakerBounds = TextService:GetTextSize(speaker, BUBBLE_SPEAKER, Enum.Font.Oswald, Vector2.new(1000, 100))
	local lineBounds =
		TextService:GetTextSize(text, BUBBLE_LINE, Enum.Font.Merriweather, Vector2.new(BUBBLE_MAX_W, 1000))
	local innerW = math.ceil(math.max(speakerBounds.X * 1.15, lineBounds.X)) + 2 -- Oswald Bold runs wider
	local speakerH = BUBBLE_SPEAKER + 4
	local lineH = math.ceil(lineBounds.Y) + 4
	local card = UIKit.new("Frame", {
		Name = "Bubble",
		BackgroundColor3 = Colors.ink,
		BackgroundTransparency = 0.06,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, state.silent and -22 or -10),
		Size = UDim2.fromOffset(innerW + padL + padR, padT + speakerH + lineH + padB),
		ZIndex = 6,
		Parent = u.box,
	}, { UIKit.corner(10), UIKit.stroke(Colors.paper, 1, 0.85) })
	UIKit.new("Frame", {
		Name = "Tab",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(0, 5, 1, -16),
		Parent = card,
	}, { UIKit.corner(3) })
	UIKit.new("TextLabel", {
		Name = "Speaker",
		Text = speaker,
		FontFace = Face.bold,
		TextSize = BUBBLE_SPEAKER,
		TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padL, padT),
		Size = UDim2.fromOffset(innerW, speakerH),
		Parent = card,
	})
	UIKit.new("TextLabel", {
		Name = "Line",
		Text = text,
		FontFace = Face.serif,
		TextSize = BUBBLE_LINE,
		TextColor3 = Colors.paper,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(padL, padT + speakerH),
		Size = UDim2.fromOffset(innerW, lineH),
		Parent = card,
	})
	tween(card, POP, { Position = UDim2.new(0.5, 0, 0, -22) })
	play("Hover", 0.1)
	if linger < math.huge then
		task.delay(linger + #text / CHARS_PER_SECOND, function()
			if not card.Parent then
				return
			end
			local fadeInfo = TweenInfo.new(0.35)
			local fade = tween(card, fadeInfo, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0, -32) })
			for _, child in card:GetChildren() do
				if child:IsA("TextLabel") then
					tween(child, fadeInfo, { TextTransparency = 1 })
				elseif child:IsA("Frame") then
					tween(child, fadeInfo, { BackgroundTransparency = 1 })
				elseif child:IsA("UIStroke") then
					tween(child, fadeInfo, { Transparency = 1 })
				end
			end
			if fade then
				fade.Completed:Wait()
			end
			card:Destroy()
		end)
	end
end

-- A short interjection ("Don't."). Idle: the box shows just the line and closes itself (click / E
-- closes it sooner). During a conversation: an ink bubble above the box, so the conversation keeps
-- its place. `hold` overrides how long it lingers once typed.
function Dialogue.say(speaker: string, text: string, accent: Color3?, hold: number?)
	local u = ensureUI()
	local color = accent or Colors.accent
	local linger = hold or SAY_HOLD
	if state.open and state.mode == "tree" then
		showBubble(speaker, text, color, linger)
		return
	end

	-- idle (or replacing an earlier interjection): the box itself carries the line
	local wasOpen = state.open
	state.mode = "say"
	state.open = true
	state.tree = nil
	state.opts = {}
	state.visible = {}
	clearChoices()
	buildPips(0)
	applyAccent(color)
	u.tab.Text = speaker
	state.voice = nil
	setLayout("say", text, 0)
	if not wasOpen then
		openBox()
	end
	state.sayToken += 1
	local token = state.sayToken
	typeLine(text, function()
		if linger < math.huge then
			task.delay(linger, function()
				if state.open and state.mode == "say" and state.sayToken == token then
					finish()
				end
			end)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Test hooks (Edit-mode previews: no LocalPlayer, tweens don't run)
------------------------------------------------------------------------------------------
-- Where the ScreenGui goes (and what it's called). Call before the first start / say / preview.
function Dialogue._setParent(parent: Instance, name: string?)
	guiParent = parent
	guiName = name or "DialogueUI"
	if ui then
		ui.gui.Name = guiName
		ui.gui.Parent = parent
	end
end

-- Render `nodeId` (default: the tree's start) fully typed, choices revealed, no sounds or tweens.
function Dialogue._preview(tree: Tree, nodeId: string?, ctx: any?): ScreenGui
	state.silent = true
	beginTree(tree, { context = ctx }, nodeId)
	return (ensureUI()).gui
end

return Dialogue
