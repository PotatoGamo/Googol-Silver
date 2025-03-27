local auto_update = true
local root_URL = "https://raw.githubusercontent.com/PotatoGamo/Googol-Silver/refs/heads/master/client/"
local version_URL = root_URL.."version"
local silver_URL = root_URL.."silver.lua"
local filelist_URL = root_URL.."filelist"
 
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
    if (not f) or version:match("[%.%w]") ~= f:read("*a"):match("[%.%w]") then
        print("Updating Silver to v"..version)
        if f then f:close() end
        
        local files = http.get(filelist_URL)
        if not files then term.setTextColor(colors.red) print("Could not retrieve file list") end
        local filelist = textutils.unserialize(files.readAll())
        files.close()
        
        local todownload = 1
        term.setTextColor(colors.green)
        function rrequest(name, t)
            for i,v in pairs(t) do
                if type(v) == "table" then
                    --print("Making folder .silver/"..name.."/"..i)
                    fs.makeDir("/.silver/"..name.."/"..i)
                    rrequest(name.."/"..i, v)
                else
                    --print("Requesting .silver/"..name.."/"..v)
                    http.request(root_URL.."silver/"..name.."/"..v)
                    todownload = todownload + 1
                end
            end
        end
        fs.makeDir("/.silver")
        rrequest("", filelist)
        
        http.request(silver_URL)
        --http.request(package_URL)
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
                --[[elseif evt[2] == package_URL then
                    pkgsaved = true
                    term.setTextColor(colors.green)
                    install(evt[3].readAll())
                    evt[3].close()
                    print("Successfully downloaded and saved the Silver filesystem package")]]
                else
                    local file = evt[2]:match("/master/(.+)"):gsub("silver", ".silver")
                    local f = io.open(file, "w")
                    f:write(evt[3].readAll())
                    f:close()
                    print("Successfully downloaded "..file)
                end
                todownload = todownload - 1
                if todownload == 0 then break end
            elseif evt[1] == "http_failure" then
                term.setTextColor(colors.red)
                print("Failed to download "..evt[2]:match("/master/(.+)"))
                print("Failed to update Silver.")
                error()
            end
        end
        
        local f2 = io.open("/.silver/version", "w")
        f2:write(version)
        f2:close()
        
        term.setTextColor(colors.green)
        print("Successfully updated Silver to v"..version)
        sleep(3)
        shell.run(shell.getRunningProgram())
        error()
    end
end
