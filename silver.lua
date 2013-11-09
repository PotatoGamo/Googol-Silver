local version = "$$VERSION"
local auto_update = true
local root_URL = "https://raw.github.com/Imgoodisher/Googol-Silver/master/"
local version_URL = root_URL.."version"
local silver_URL = root_URL.."silver.lua"
local package_URL = root_URL.."silver-package.lua"

local w, h = term.getSize()

-- Installer
function install(o)
	setfenv(assert(loadstring(o), "Corrupt File Package/Bad HTTP Request"), setmetatable({shell=shell},{__index=_G}))(".silver")
end

term.setBackgroundColor(colors.white)
term.setTextColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
print("Updating Silver...")
if auto_update then
	local f = http.get(version_URL)
	local version = f.readAll()
	f.close()
	
	local f = io.open("/.silver/version", "r")
	if (not f) or version ~= f:read("*a") then
		print("Updating Silver to v"..version)
		if f then f:close() end
		
		http.request(silver_URL)
		http.request(package_URL)
		local silversaved, pkgsaved = false, false
		while true do
			local evt = {os.pullEvent()}
			if evt[1] == "http_success" then
				if evt[2] == silver_URL then
					silversaved = true
					local v = io.open(shell.getRunningProgram(), "w")
					v:write(evt[3].readAll():gsub("$$VERSION", version))
					v:close()
					evt[3].close()
					term.setTextColor(colors.green)
					print("Successfully downloaded and saved Silver")
				elseif evt[2] == package_URL then
					pkgsaved = true
					term.setTextColor(colors.green)
					install(evt[3].readAll())
					evt[3].close()
					print("Successfully downloaded and saved the Silver filesystem package")
				end
				if silversaved and pkgsaved then break end
			else
				term.setTextColor(colors.red)
				print("Failed to download "..evt[2])
				print("Failed to update Silver.")
				error()
			end
		end
		
		term.setTextColor(colors.green)
		print("Successfully updated Silver to v"..version)
		sleep(3)
		shell.run(shell.getRunningProgram())
		error()
	end
	local f2 = io.open("/.silver/version", "w")
	f2:write(version)
	f2:close()
end


os.loadAPI(".silver/apis/redirect")

--local buffer = redirect.createRedirectBuffer(w, h)
--term.redirect(buffer)
--buffer.makeActive()


-- Load Addons
local addons = {}
for i,v in pairs(fs.list(".silver/addons")) do
	local on = function(event, func)
		if not addons[event] then addons[event] = {} end
		table.insert(addons[event], func)
	end
	if fs.isDir(".silver/addons/"..v) then
		os.run({on = on}, ".silver/addons/"..v.."/init")
	else
		os.run({on = on}, ".silver/addons/"..v)
	end
end
function doEvent(event, ...)
	if addons[event] then
		for i, v in pairs(addons[event]) do
			v(...)
		end
	end
end
doEvent("before-load")


local term_setBackgroundColor = term.setBackgroundColor
local bgcolor = colors.black
local term_setTextColor = term.setTextColor
local textcolor = colors.white
local term_setCursorBlink = term.setCursorBlink
local blink = false
term.setBackgroundColor = function(col)
	bgcolor = col
	term_setBackgroundColor(col)
end
term.setTextColor = function(col)
	textcolor = col
	term_setTextColor(col)
end
term.setCursorBlink = function(bl)
	blink = bl
	term_setCursorBlink(bl)
end


for i, v in pairs(rs.getSides()) do
	if peripheral.getType(v) == "modem" then
		rednet.open(v)
	end
end

local savedata = {}
if fs.exists("/.silver/savedata") then
	local f = io.open("/.silver/savedata", "r")
	savedata = textutils.unserialize(f:read("*a"))
	f:close()
end

silver = {
	urls = {},
	timeout = 0.10,
	headers = {
		["User-Agent"] = "Silver/"..version.." ("..os.version().." "..(term.isColor() and "Color" or "Basic")..")",
	},
	address_focused = true,
	page_buffer = {},
	address = "about:home",
	current_page = "",
	
	env = {},
	
	themes = {},
	theme = "default",
	setTheme = function(name)
		silver.theme = name
		silver.env.theme.theme = silver.themes[name]
	end,
	listThemes = function()
		local list = {}
		for i,v in pairs(silver.themes) do
			table.insert(list, i)
		end
		return list
	end,
	getThemeVal = function(val)
		return (silver.themes[silver.theme] and silver.themes[silver.theme][val]) or silver.themes["default"][val] or 1
	end,
	
	escape = function(str)
		return tostring(str):gsub("([^%w/#%?])", function(s)
			return "%"..(s:byte()<10 and "0" or "")..s:byte()
		end)
	end,
	unescape = function(str)
		return tostring(str):gsub("%%(%d%d)", function(s)
			return string.char(tonumber(s));
		end)
	end,
	receive = function(id, timeout)
		local start = os.clock()
		while true do
			local _id, msg = rednet.receive(timeout)
			if (_id == id) then
				return msg
			end
			if start - os.clock() < timeout then return false end
		end
	end,
	
	
	sandbox = function(func, env_add, redirect)
		init_sandbox()
		local env = {}
		for i, v in pairs(silver.env) do
			env[i] = v
		end
		for i, v in pairs(env_add) do
			env[i] = v
		end
		if redirect then
			for i,v in pairs(env.term) do
				if not redirect[i] then redirect[i] = v end
			end
			env.term = redirect
		end
		return setfenv(func, setmetatable({}, {__index = env}));
	end,
	
	protocols = {
		rttp = {
			list = function()
				rednet.broadcast("LIST * RTTP/1.0")
				local l = {}
				local start = os.clock()
				while true do
					local id, msg = rednet.receive(silver.timeout)
					if not id then break end
					local url, headers = msg:match("([^%s]+)%s?(.*)")
					if url then
						table.insert(l, url)
						silver.urls[url] = {}
						silver.urls[url].id = id
						headers:gsub('([^:]+):%s?([^\n]+)\n', function(k, v)
							silver.urls[url][k] = v
						end)
					end
					if os.clock() - start > silver.timeout then break end
				end
				return l;
			end,
			get = function(url, search, headers)
				local host, page = url:match("^([^/]+)(.*)$")
				silver.protocols.rttp.list();
				if silver.urls[host] and tonumber(silver.urls[host].id) then
					local s = 'GET '..silver.escape(page)..' RTTP/1.0\n'
					for i, v in pairs(headers or {}) do
						s = s .. i .. ": " .. v .. "\n"
					end
					s = s .. "\n"
					rednet.send(silver.urls[host].id, s)
					local msg = silver.receive(silver.urls[host].id, silver.timeout)
					if msg then
						local stat, head, body = msg:match("^(%d+)%s.-\n(.-)\n\n(.+)$")
						if stat then
							local headers = {}
							head:gsub('([^:]+):%s?([^\n]+)\n', function(k, v)
								headers[k] = v
							end)
							return body, headers
						else
							return silver.protocols.about.get("error/invalid")
						end
					else
						return silver.protocols.about.get("error/timeout")
					end
				else
					return silver.protocols.about.get("error/unknown")
				end
			end,
		},
		about = {
			list = function()
				return fs.list(".silver/pages")
			end,
			get = function(url)
				local f = io.open(".silver/pages/"..url, "r")
				if (f) then
					local data = f:read("*a")
					f:close()
					return data, {["Content-Type"]="text/lua"}
				else
					return 'print("") cPrint("'..url..' not found")', {["Content-Type"]="text/lua"}
				end
			end,
		}
	},
	filetypes = {
		["text/lua"] = function(body, headers)
			return loadstring(body)
		end,
	},
	
	navigate = function(uri)
		--goroutine.kill("page")
		sleep(0)
		--silver.address = uri
		local protocol, url, hash, search, status, body, headers, func, err
		if not uri:match("^([^%.]-):") then
			if uri == silver.address then silver.address = "rttp:"..silver.address end
			protocol = "rttp"
			url = uri:match("^([^#%?]*)#?([^%?]*)%??(.*)$")
		else
			protocol, url, hash, search = uri:match("^([^:]+):/?/?([^#%?]*)#?([^%?]*)%??(.*)$")
		end
		if silver.protocols[protocol] and silver.protocols[protocol].get then
			local _head = {}
			if search then _head.search = search end
			for i,v in pairs(silver.headers) do
				_head[i] = v
			end
			body, headers = silver.protocols[protocol].get(url, search, _head)
		else
			status = 0
			body = 'cPrint("Error") cPrint("Unknown protocol")'
			headers = {["Content-Type"]="text/lua"}
		end
		if type(headers) ~= "table" then headers = {} end
		if not headers["Content-Type"] then headers["Content-Type"] = "text/lua" end
		if silver.filetypes[headers["Content-Type"]] then
			func, err = silver.filetypes[headers["Content-Type"]](body, headers)
		end
		
		if not func then
			return silver.navigate("about:error/page?name="..silver.escape(url).."&msg="..silver.escape(err))
		end
		
		silver.current_page = protocol..":"..url
		
		init_sandbox()
		local w, h = term.getSize()
		silver.page_co = coroutine.create(silver.sandbox(func, {headers=headers, err=err, address={protocol=protocol, url=url, hash=hash, search=search}}--[[, silver.page_buffer]]))
		term.setTextColor(colors.white)
		term.setBackgroundColor(colors.black)
		term.clear()
		term.setCursorPos(1, 2)
		term.setCursorBlink(false)
		coroutine.resume(silver.page_co)
		draw()
	end,
}

-- Load Themes
silver.themes = {}
for i, v in pairs(fs.list("/.silver/themes")) do
	local f = io.open("/.silver/themes/"..v, "r")
	local ok, t = pcall(loadstring("return " .. f:read("*a")))
	if ok then silver.themes[v] = t else print("Error loading theme "..v..": "..t) sleep(2) end
	f:close()
end
silver.theme = savedata.theme or "default"



-- Address bar drawing
local pos = silver.address:len()
local scroll = 0
function draw()
	local bc, tc = bgcolor, textcolor
	local x, y = term.getCursorPos()
	local w, h = term.getSize()
	term.setCursorPos(1, 1)
	term.setBackgroundColor(silver.getThemeVal("address-bar-background"))
	term.setTextColor(silver.getThemeVal("address-bar-text"))
	term.write((" "):rep(w))
	term.setCursorPos(1, 1)
	term.write(silver.address:sub(scroll+1, scroll+w-3+1))
	if silver.address_focused then
		term.setCursorPos(pos+1, 1)
		term.setBackgroundColor(silver.getThemeVal("address-bar-cursor"))
		term.write(pos+scroll < silver.address:len() and silver.address:sub(pos+scroll+1, pos+scroll+1) or " ")
		term.setBackgroundColor(silver.getThemeVal("address-bar-background"))
	end
	term.setCursorPos(w, 1)
	term.setTextColor(silver.getThemeVal("exit-button-color"))
	term.write("X")
	
	term.setCursorPos(x, y)
	term.setBackgroundColor(bc)
	term.setTextColor(tc)
end


-- Set up sandbox environment
function init_sandbox()
	silver.env = {}
	local apis = {"math", "string", "table", "textutils", "coroutine", "colors", "colours", "keys", "parallel", "term"}
	for i, v in pairs(apis) do
		silver.env[v] = {}
		for h, k in pairs(_G[v]) do
			silver.env[v][h] = k
		end
	end
	local funcs = {"read", "write", "print", "sleep", "tostring", "tonumber", "setmetatable", "getmetatable", "pcall", "type", "pairs"}
	for i, v in pairs(funcs) do
		silver.env[v] = _G[v]
	end
	
	silver.env.os = {}
	for i, v in pairs(os) do
		if i ~= "shutdown" and i ~= "reboot" and i ~= "queueEvent" then
			silver.env.os[i] = v
		end
	end
	
	for i,v in pairs(term) do
		if not silver.env.term[i] then silver.env.term[i] = v end
	end
	
	silver.env.loadstring = function(str)
		local f, err = loadstring(str)
		if not f then return false, err end
		return setfenv(f, silver.env)
	end

	silver.env.silver = {
		navigate = function(page) os.queueEvent("redirect", page) end,
		setTheme = silver.setTheme,
		listThemes = silver.listThemes,
		receive = silver.receive,
		sandbox = silver.sandbox,
		escape = silver.escape,
		unescape = silver.unescape,
	}
	for i, v in pairs(silver.env.silver) do
		silver.env[i] = v
	end
	silver.env.silver.protocols = {}
	for i, v in pairs(silver.protocols) do
		silver.env.silver.protocols[i] = {}
		silver.env[i] = {}
		for h, k in pairs(v) do
			silver.env.silver.protocols[i][h] = k
			silver.env[i][h] = k
		end
	end
	silver.env.silver.filetypes = {}
	for i, v in pairs(silver.filetypes) do
		silver.env.silver.filetypes[i] = v
	end
	
	silver.env.theme = {
		get = function(val)
			return (silver.themes[silver.theme] and silver.themes[silver.theme][val]) or silver.themes["default"][val] or 1
		end
	}

	silver.env.cPrint = function(text) 
		local w, h = term.getSize()
		local x, y = term.getCursorPos()
		term.setCursorPos(w/2-text:len()/2, y)
		print(text)
	end
	silver.env.tWrite = function(text)
		local function draw(part, col)
			print(part)
			if col ~= "" then term.setTextColor(2^(tonumber(col,16)-1)) end
			return ""
		end
		draw(text:gsub("(.-)&([%x])", draw), "")
		--[[text:gmatch("&?([1-16]?)([^&])", function(c, t)
			term.setTextColor((c:byte()-1)^16)
			term.write(t)
		end)]]
	end
	silver.env.import = function(uri)
		local protocol, url, status, body, headers, func, err
		if not uri:match("^([^%.]-):") then
			protocol = "rttp"
			url = uri
		else
			protocol, url = uri:match("^([^:]+):/?/?(.+)$")
		end
		if silver.protocols[protocol] and silver.protocols[protocol].get then
			body, headers = silver.protocols[protocol].get(url)
			local func, err = loadstring(body)
			if func then
				func()
				return true
			else 
				return false, err 
			end
		end
		return false
	end
	
	local tColourLookup = {}
	for n=1,16 do
		tColourLookup[ string.byte( "0123456789abcdef",n,n ) ] = 2^(n-1)
	end
	silver.env.loadImage = function( str )
		local tImage = {}
		for sLine in str:gmatch("[^\n]+") do
			local tLine = {}
			for x=1,sLine:len() do
				tLine[x] = tColourLookup[ string.byte(sLine,x,x) ] or 0
			end
			table.insert( tImage, tLine )
		end
		return setfenv(function(xPos, yPos) 
			for y=1,#tImage do
				local tLine = tImage[y]
				for x=1,#tLine do
					if tLine[x] > 0 then
						term.setBackgroundColor( tLine[x] )
						drawPixelInternal( x + xPos - 1, y + yPos - 1 )
					end
				end
			end
		end, {
			term = term,
			drawPixelInternal = function( xPos, yPos )
				term.setCursorPos(xPos, yPos)
				term.write(" ")
			end
		})
	end
end




-- Main function
function main()
	term.clear()
	local w, h = term.getSize()
	silver.navigate(silver.address)
	
	draw()
	
	while true do
		local evt = {os.pullEvent()}
		if evt[1] == "key" then
			if evt[2] == keys.leftCtrl then
				silver.address_focused = not silver.address_focused
				term_setCursorBlink(((not silver.address_focused) and blink) or false)
				draw()
			elseif evt[2] == keys.f5 then
				silver.navigate(silver.current_page)
			end
		elseif evt[1] == "mouse_click" then
			if evt[3] == w and evt[4] == 1 then
				break
			end
			silver.address_focused = evt[4] == 1
			term_setCursorBlink(((not silver.address_focused) and blink) or false)
			pos = math.min(math.max((evt[4]==1 and evt[3]-1) or pos, 0), silver.address:len()-scroll)
			draw()
		elseif evt[1] == "redirect" then
			silver.address = evt[2]
			silver.navigate(evt[2])
			draw()
		end
		if silver.address_focused then
			if evt[1] == "char" then
				silver.address = silver.address:sub(1, pos+scroll) .. evt[2] .. silver.address:sub(pos+scroll + 1)
				pos = pos + 1
				if pos > w-3 then pos=pos-1 scroll=math.min(scroll+1, silver.address:len()-w+3) end
				draw()
			elseif evt[1] == "key" then
				if evt[2] == keys.enter then
					if silver.address == "exit" then
						break
					end
					silver.address_focused = false
					term_setCursorBlink(blink)
					silver.navigate(silver.address)
					draw()
					--silver.page_buffer.makeActive()
				elseif evt[2] == keys.left then
					pos = pos-1
					if pos < 0 then pos=0 scroll=math.max(scroll-pos-1, 0) end
					draw()
				elseif evt[2] == keys.right then
					pos = math.min(silver.address:len(), pos+1)
					if pos > w-3 then pos=pos-1 scroll=math.min(scroll+1, silver.address:len()-w+3) end
					draw()
				elseif evt[2] == keys.backspace then 
					if pos > 0 then
						silver.address = silver.address:sub(1, pos+scroll-1) .. silver.address:sub(pos+scroll+1)
						if scroll > 0 then
							scroll=math.max(scroll-1)
						else
							pos = math.max(pos - 1, 0)
						end
					end
					draw()
				elseif evt[2] == keys.home then
					pos = 0
					scroll = 0
					draw()
				elseif evt[2] == keys.delete then
					if pos < silver.address:len() then
						silver.address = silver.address:sub(1, pos)..silver.address:sub(pos+2)
					end
					draw()
				elseif evt[2] == keys["end"] then
					pos = silver.address:len()
					if pos > w-3 then scroll=pos-w-3 pos=w-3 end
					draw()
				end
			end
		else
			if evt[1] == "mouse_click" or evt[1] == "mouse_drag" then
				evt[4] = evt[4] - 1
			end
			if coroutine.status(silver.page_co) ~= "dead" then
				local ok, err = coroutine.resume(silver.page_co, unpack(evt))
				if not ok then
					silver.navigate("about:error/page?name="..silver.escape(silver.current_page).."&msg="..silver.escape(err))
				end
			end
		end
	end
	term.clear()
	term.setCursorPos(1, 1)
end

local ok, err = pcall(main)
term.restore()
term.setTextColor(colors.white)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then print(err) end
doEvent("exit")