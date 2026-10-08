--!strict
-- Books: fills a bookcase shelf with individual books (series runs, leaning books, flat stacks,
-- bookends and gaps) plus cheap spine details (gilt bands, title labels).
--
-- Coordinates are shelf-local via `at(x, y, z)`: X runs along the shelf, Y is up, +Z faces the
-- reader. Spines face away from the shelf centre: +Z when zCenter >= 0, -Z when zCenter < 0.

local Books = {}

local MAX_HEIGHT = 2.05
local PARTS_PER_STUD = 60 / 12 -- performance budget (books + details) per stud of shelf

-- Library palette; duplicates act as weights.
local PALETTE = {
	Color3.fromRGB(104, 22, 22), -- oxblood
	Color3.fromRGB(104, 22, 22),
	Color3.fromRGB(132, 34, 28), -- red
	Color3.fromRGB(34, 60, 38), -- bottle green
	Color3.fromRGB(34, 60, 38),
	Color3.fromRGB(26, 44, 32), -- deep green
	Color3.fromRGB(26, 36, 66), -- navy
	Color3.fromRGB(26, 36, 66),
	Color3.fromRGB(42, 56, 90), -- slate blue
	Color3.fromRGB(150, 106, 38), -- ochre
	Color3.fromRGB(166, 130, 86), -- tan
	Color3.fromRGB(92, 58, 34), -- brown
	Color3.fromRGB(92, 58, 34),
	Color3.fromRGB(62, 38, 24), -- dark brown
	Color3.fromRGB(24, 22, 22), -- black
	Color3.fromRGB(78, 30, 50), -- plum
	Color3.fromRGB(212, 198, 164), -- vellum
}
local GOLD = Color3.fromRGB(196, 154, 70)
local CREAM = Color3.fromRGB(226, 212, 174)
local DARK_LABEL = Color3.fromRGB(22, 20, 18)
local BOOKEND = Color3.fromRGB(64, 52, 38)

type Series = {
	color: Color3,
	material: Enum.Material,
	height: number,
	width: number,
	depth: number,
	bands: number, -- 0, 1 or 2 bands at each end
	bandColor: Color3,
	label: boolean,
	labelColor: Color3,
}

type Book = {
	cf: CFrame, -- centre; local Y = book height axis, local Z = spine axis (sign via `s`)
	size: Vector3,
	series: Series,
}

local function newPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material
)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local function vary(rng: Random, c: Color3, amount: number): Color3
	local k = 1 + rng:NextNumber(-amount, amount)
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

local function newSeries(rng: Random, depth: number): Series
	local color = PALETTE[rng:NextInteger(1, #PALETTE)]
	local light = color.R + color.G + color.B > 1.6
	local bandRoll = rng:NextNumber()
	return {
		color = color,
		material = Enum.Material.SmoothPlastic,
		height = rng:NextNumber(1.25, 1.95),
		width = rng:NextNumber(0.2, 0.42),
		depth = math.min(rng:NextNumber(0.9, 1.3), depth),
		bands = bandRoll < 0.3 and 0 or bandRoll < 0.75 and 1 or 2,
		bandColor = light and DARK_LABEL or (rng:NextNumber() < 0.8 and GOLD or CREAM),
		label = rng:NextNumber() < 0.3,
		labelColor = light and DARK_LABEL or (rng:NextNumber() < 0.6 and CREAM or Color3.fromRGB(30, 26, 22)),
	}
end

function Books.fillShelf(
	parent: Instance,
	at: (number, number, number) -> CFrame,
	length: number,
	y: number,
	zCenter: number,
	depth: number,
	rng: Random
)
	local s = zCenter < 0 and -1 or 1 -- spine direction (shelf-local Z)
	local zFront = zCenter + s * depth / 2
	-- Rotation that makes a book's local +Z point along the spine direction.
	local face = s > 0 and CFrame.identity or CFrame.Angles(0, math.pi, 0)

	local xMin = -length / 2 + 0.05
	local xMax = length / 2 - 0.05
	local books: { Book } = {}
	local count = 0

	local function spineZ(d: number): number
		local inset = rng:NextNumber() < 0.12 and rng:NextNumber(0.06, 0.16) or rng:NextNumber(0, 0.04)
		return zFront - s * (d / 2 + inset)
	end

	local function addBook(cf: CFrame, size: Vector3, series: Series)
		newPart(parent, "Book", size, cf, vary(rng, series.color, 0.1), series.material)
		count += 1
		table.insert(books, { cf = cf, size = size, series = series })
	end

	local x = xMin
	local prevHeight: number? = nil -- height of the upright book ending at x (for leaning)
	local series = newSeries(rng, depth)
	local runLeft = rng:NextInteger(2, 7)

	while x < xMax - 0.2 do
		local roll = rng:NextNumber()
		local room = xMax - x

		if roll < 0.05 and x > xMin + 1 and room > 1.5 then
			-- empty gap
			x += rng:NextNumber(0.4, 1.1)
			prevHeight = nil
		elseif roll < 0.11 and room > 1.9 then
			-- flat stack of 2-4 books
			local n = rng:NextInteger(2, 4)
			local lengths = {}
			for i = 1, n do
				lengths[i] = rng:NextNumber(1.2, 1.75)
			end
			table.sort(lengths, function(a, b)
				return a > b
			end)
			local span = lengths[1]
			local cx = x + 0.04 + span / 2
			local yy = y
			for i = 1, n do
				local st = newSeries(rng, depth)
				local t = rng:NextNumber(0.16, 0.32)
				if yy + t - y > MAX_HEIGHT then
					break
				end
				local d = st.depth
				local cf = at(cx + rng:NextNumber(-0.06, 0.06), yy + t / 2, spineZ(d))
					* face
					* CFrame.Angles(0, math.rad(rng:NextNumber(-3, 3)), math.pi / 2)
				addBook(cf, Vector3.new(t, lengths[i], d), st)
				yy += t
			end
			x += span + 0.1
			prevHeight = nil
		elseif roll < 0.14 and prevHeight and room > 1 then
			-- bookend after a run, then a small gap
			local h = rng:NextNumber(0.8, 1.0)
			newPart(
				parent,
				"Bookend",
				Vector3.new(0.08, h, 0.7),
				at(x + 0.05, y + h / 2, zFront - s * 0.45),
				BOOKEND,
				Enum.Material.Metal
			)
			count += 1
			x += 0.1 + rng:NextNumber(0.2, 0.6)
			prevHeight = nil
		elseif roll < 0.22 and prevHeight then
			-- leaning book resting on the upright neighbour to its left (top tilts toward -X)
			local hn = prevHeight :: number
			local st = rng:NextNumber() < 0.5 and series or newSeries(rng, depth)
			local w = math.clamp(st.width + rng:NextNumber(-0.04, 0.04), 0.18, 0.45)
			local h = math.clamp(st.height + rng:NextNumber(-0.1, 0.05), 1.2, MAX_HEIGHT)
			local theta = math.rad(rng:NextNumber(8, 18))
			local c, sn = math.cos(theta), math.sin(theta)
			local px = if h * c >= hn then x + hn * math.tan(theta) else x + h * sn
			if px + w * c > xMax then
				break
			end
			local cx = px + w / 2 * c - h / 2 * sn
			local cy = y + w / 2 * sn + h / 2 * c
			local d = st.depth
			local cf = at(cx, cy, spineZ(d)) * CFrame.Angles(0, 0, theta) * face
			addBook(cf, Vector3.new(w, h, d), st)
			x = px + w * c + rng:NextNumber(0.02, 0.3)
			prevHeight = nil
		else
			-- upright book from the current series run
			if runLeft <= 0 then
				series = newSeries(rng, depth)
				runLeft = rng:NextInteger(1, 7)
				x += rng:NextNumber() < 0.3 and rng:NextNumber(0.02, 0.08) or 0
			end
			runLeft -= 1
			local w = math.clamp(series.width + rng:NextNumber(-0.03, 0.03), 0.18, 0.45)
			if x + w > xMax then
				w = xMax - x
				if w < 0.18 then
					break
				end
			end
			local h = math.clamp(series.height + rng:NextNumber(-0.06, 0.06), 1.2, MAX_HEIGHT)
			local d = series.depth
			addBook(at(x + w / 2, y + h / 2, spineZ(d)) * face, Vector3.new(w, h, d), series)
			x += w + (rng:NextNumber() < 0.25 and rng:NextNumber(0.005, 0.03) or 0.003)
			prevHeight = h
		end
	end

	-- Spine details, thinned evenly to fit the part budget.
	local total = math.floor(PARTS_PER_STUD * length)
	local budget = total - count
	local wanted = 0
	for _, b in books do
		wanted += b.series.bands * 2 + (b.series.label and 1 or 0)
	end
	if budget <= 0 or wanted == 0 then
		return
	end
	local keep = math.min(1, budget / wanted)
	for _, b in books do
		local st, size = b.series, b.size
		local zOut = size.Z / 2
		local bw = size.X - 0.02
		if st.bands > 0 and count + st.bands * 2 <= total and rng:NextNumber() < keep then
			-- band pairs near top and bottom
			local bh = 0.05
			for i = 1, st.bands do
				local off = size.Y / 2 - 0.12 - (i - 1) * 0.1
				for _, sign in { 1, -1 } do
					newPart(
						parent,
						"BookBand",
						Vector3.new(bw, bh, 0.04),
						b.cf * CFrame.new(0, sign * off, zOut),
						st.bandColor,
						Enum.Material.SmoothPlastic
					)
					count += 1
				end
			end
		end
		if st.label and size.Y > 1 and count < total and rng:NextNumber() < keep then
			newPart(
				parent,
				"BookLabel",
				Vector3.new(math.max(bw * 0.62, 0.1), 0.3, 0.04),
				b.cf * CFrame.new(0, size.Y * 0.18, zOut),
				st.labelColor,
				Enum.Material.SmoothPlastic
			)
			count += 1
		end
	end
end

return Books
