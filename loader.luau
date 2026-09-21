type ExplorerNode = {
    obj: Instance?,
    name: string?,
    className: string?,
    parent: ExplorerNode?,
    depth: number,
    expanded: boolean,
    loaded: boolean,
    children: {ExplorerNode},
    pseudo: boolean,
    hasChildren: boolean?,
    sortDirty: boolean,
}
type DockState = {
    Side: string,
    Docked: boolean,
    Width: number,
    FloatingSize: Vector2,
    FloatingPosition: Vector2?,
    SnapDistance: number,
    RespectGuiInset: boolean,
    TopGap: number,
    BottomGap: number,
    BottomOverscan: number,
    Collapsed: boolean,
}
type PropertyEntry = {
    Name: string,
    Category: string?,
    ValueType: string?,
    ValueCategory: string?,
    Special: string?,
    AttrName: string?,
    ComponentKey: string?,
    ParentProp: PropertyEntry?,
    ReadOnly: boolean?,
    Collapsed: boolean?,
    [string]: any,
}
type IconWarmupState = {Total: number, Ready: number, Failed: number, Completed: number, Current: string}
local runtimeutil = {}
local cachestore = {}
local uifactory = {}
local dockcontroller = {}
local loadingcontroller = {}
local layoutcontroller = {}
local viewercontroller = {}
local treecontroller = {}
local valuecodec = {}
local propertycontroller = {}
local menucontroller = {}
local iconcontroller = {}
local rawgame = game
function runtimeutil.CloneRef(x: any): any
    if type(cloneref) == "function" then
        local ok, out = pcall(cloneref, x)
        if ok then return out end
    end
    return x
end

local services = setmetatable({}, {
    __index = function(t, k)
        local v = runtimeutil.CloneRef(rawgame:GetService(k))
        rawset(t, k, v)
        return v
    end
})

local players = services.Players
local uis = services.UserInputService
local guiservice = services.GuiService
local httpservice = services.HttpService
local contentprovider = services.ContentProvider

local studioservice = nil
do
    local ok, service = pcall(function()
        return rawgame:GetService("StudioService")
    end)

    if ok then
        studioservice = service
    end
end
local textservice = services.TextService
local runservice = services.RunService
local coregui = services.CoreGui
local localplayer = players.LocalPlayer

function runtimeutil.Try(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

function runtimeutil.Trim(s: any): string
    return tostring(s):match("^%s*(.-)%s*$")
end

function runtimeutil.Clamp(n: number, a: number, b: number): number
    if n < a then return a end
    if n > b then return b end
    return n
end

function runtimeutil.Disconnect(c: RBXScriptConnection?)
    if c then pcall(function() c:Disconnect() end) end
end

local runtimeadapter = {}
runtimeadapter.__index = runtimeadapter

function runtimeadapter.new()
    local self = setmetatable({}, runtimeadapter)
    self.gethui = type(gethui) == "function" and gethui or type(get_hidden_gui) == "function" and get_hidden_gui or nil
    self.setclipboard = type(setclipboard) == "function" and setclipboard or type(toclipboard) == "function" and toclipboard or type(set_clipboard) == "function" and set_clipboard or nil
    self.decompile = type(decompile) == "function" and decompile or nil
    self.getnilinstances = type(getnilinstances) == "function" and getnilinstances or type(get_nil_instances) == "function" and get_nil_instances or nil
    self.readfile = type(readfile) == "function" and readfile or nil
    self.writefile = type(writefile) == "function" and writefile or nil
    self.makefolder = type(makefolder) == "function" and makefolder or nil
    self.isfile = type(isfile) == "function" and isfile or nil
    self.request = type(request) == "function" and request or type(http_request) == "function" and http_request or (type(syn) == "table" and type(syn.request) == "function" and syn.request) or nil
    self.getcustomasset = type(getcustomasset) == "function" and getcustomasset or type(getsynasset) == "function" and getsynasset or nil
    self.protectgui = (type(syn) == "table" and type(syn.protect_gui) == "function" and syn.protect_gui) or (type(protectgui) == "function" and protectgui) or (type(protect_gui) == "function" and protect_gui) or nil
    self.listfiles = type(listfiles) == "function" and listfiles or nil
    self.fireclickdetector = type(fireclickdetector) == "function" and fireclickdetector or nil
    self.fireproximityprompt = type(fireproximityprompt) == "function" and fireproximityprompt or nil
    self.firetouchinterest = type(firetouchinterest) == "function" and firetouchinterest or nil
    self.saveinstance = type(saveinstance) == "function" and saveinstance or type(savegame) == "function" and savegame or (type(syn) == "table" and type(syn.saveinstance) == "function" and syn.saveinstance) or nil
    return self
end

local adapter = runtimeadapter.new()

function runtimeadapter:HttpBytes(url: string): string?
    if self.request then
        local ok, res = pcall(self.request, {
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "Explorer/0.5.7",
            },
        })

        if ok and type(res) == "table" then
            local status = res.StatusCode or res.Status or 0
            local body = res.Body

            if status >= 200 and status < 300 and type(body) == "string" then
                return body
            end
        end
    end

    local ok, body = pcall(function()
        return rawgame:HttpGet(url)
    end)

    if ok and type(body) == "string" and #body > 0 then
        return body
    end

    return nil
end

function runtimeadapter:GetGuiParent(): Instance?
    if self.gethui then
        local ok, parent = pcall(self.gethui)
        if ok and parent then return parent end
    end

    local ok = pcall(function() return coregui:GetFullName() end)
    if ok then return coregui end

    return localplayer and localplayer:FindFirstChildWhichIsA("PlayerGui")
end

function runtimeadapter:Copy(text: any): boolean
    if self.setclipboard then
        pcall(self.setclipboard, tostring(text))
        return true
    end
    return false
end

function runtimeadapter:Decompile(obj: Instance): (string?, string?)
    if not self.decompile then
        return nil, "decompile() is not available in this environment"
    end
    local ok, src = pcall(self.decompile, obj)
    if ok and type(src) == "string" then
        return src
    end
    return nil, tostring(src)
end

local metadataprovider = {}
metadataprovider.__index = metadataprovider

function metadataprovider.new()
    return setmetatable({
        Classes = {},
        Enums = {},
        RMDClasses = {},
        PropertyCache = {},
        Ready = false,
        RMDReady = false,
        Version = "unknown",
        Error = nil,
    }, metadataprovider)
end

local metadata = metadataprovider.new()

function cachestore.Read(path: string): string?
    if not adapter.readfile then return nil end
    if adapter.isfile then
        local ok, exists = pcall(adapter.isfile, path)
        if not ok or not exists then return nil end
    end
    local ok, data = pcall(adapter.readfile, path)
    return ok and data or nil
end

function cachestore.Write(path: string, data: string)
    if not (adapter.writefile and adapter.makefolder) then return end
    pcall(adapter.makefolder, "Explorer")
    pcall(adapter.writefile, path, data)
end

function cachestore.HttpGet(url: string): string?
    local ok, data = pcall(function()
        return rawgame:HttpGet(url)
    end)
    if ok and type(data) == "string" and #data > 0 then
        return data
    end
    return nil
end

function cachestore.XmlUnescape(s: string?): string?
    if not s then return s end
    return (s
        :gsub("&lt;", "<")
        :gsub("&gt;", ">")
        :gsub("&quot;", "\"")
        :gsub("&apos;", "'")
        :gsub("&amp;", "&"))
end

local studioassetsources = {
    {
        Metadata = "https://raw.githubusercontent.com/SixZensED/Explorer/main/studio-assets/ReflectionMetadata.xml",
        Icons = "https://raw.githubusercontent.com/SixZensED/Explorer/main/studio-assets/icons/",
    },
    {
        Metadata = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml",
        Icons = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/studio-svg-textures/Shared/InsertableObjects/Dark/Standard/",
    },
}

function metadataprovider:LoadReflectionMetadata(): boolean
    local cachepath = "Explorer/reflection_metadata.xml"
    local raw = cachestore.Read(cachepath)
    local fromcache = raw ~= nil

    if not raw then
        for _, source in studioassetsources do
            local body = cachestore.HttpGet(source.Metadata)

            if body and body:find("ReflectionMetadataClass", 1, true) then
                raw = body
                break
            end
        end
    end

    if not raw then
        return false
    end

    if not fromcache then
        cachestore.Write(cachepath, raw)
    end

    local classes = {}

    for block in raw:gmatch('<Item%s+class="ReflectionMetadataClass">(.-)</Item>') do
        local props = block:match("<Properties>(.-)</Properties>")
        if props then
            local name = props:match('<string%s+name="Name">(.-)</string>')
            if name then
                name = cachestore.XmlUnescape(name)

                local order =
                    props:match('<string%s+name="ExplorerOrder">(.-)</string>')
                    or props:match('<int%s+name="ExplorerOrder">(.-)</int>')

                local image =
                    props:match('<string%s+name="ExplorerImageIndex">(.-)</string>')
                    or props:match('<int%s+name="ExplorerImageIndex">(.-)</int>')

                local category =
                    props:match('<string%s+name="ClassCategory">(.-)</string>')

                classes[name] = {
                    ExplorerOrder = tonumber(order),
                    ExplorerImageIndex = tonumber(image),
                    ClassCategory = cachestore.XmlUnescape(category),
                }
            end
        end
    end

    self.RMDClasses = classes
    self.RMDReady = next(classes) ~= nil
    return self.RMDReady
end

function metadataprovider:GetExplorerOrder(classname: string): number?
    local entry = self.RMDClasses[classname]
    return entry and entry.ExplorerOrder or nil
end

function metadataprovider:GetExplorerImageIndex(classname: string): number?
    local entry = self.RMDClasses[classname]
    return entry and entry.ExplorerImageIndex or nil
end

function metadataprovider:GetClass(classname: string): any
    return self.Classes[classname]
end

function metadataprovider:GetSuperclassName(classname: string): string?
    local cls = self.Classes[classname]
    return cls and cls.SuperclassName or nil
end

function metadataprovider:GetEnumItems(enumname: string?): {any}
    if not enumname then
        return {}
    end

    enumname = tostring(enumname):gsub("^Enum%.", "")
    local src = self.Enums[enumname]
    if not src then
        return {}
    end

    local out = {}

    for name, value in src do
        out[#out + 1] = {
            Name = name,
            Value = value,
            FullName = "Enum." .. enumname .. "." .. name,
        }
    end

    table.sort(out, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)

    return out
end

function metadataprovider:IsServiceClass(classname: string): boolean
    local cls = self.Classes[classname]
    if cls and cls.Tags and cls.Tags.Service then
        return true
    end

    return tostring(classname):match("Service$") ~= nil
end

function metadataprovider:Load(): boolean
    local versionpath = "Explorer/api_version.txt"
    local version = nil
    local cachedversion = cachestore.Read(versionpath)

    if cachedversion then
        local stamp, cachedname = cachedversion:match("^(%d+)|(.+)$")

        if stamp and cachedname and os.time() - tonumber(stamp) < 21600 then
            version = cachedname
        end
    end

    if not version then
        local rawversion = cachestore.HttpGet("https://clientsettingscdn.roblox.com/v2/client-version/WindowsStudio64")

        if rawversion then
            local okversion, decodedversion = pcall(httpservice.JSONDecode, httpservice, rawversion)

            if okversion
                and type(decodedversion) == "table"
                and type(decodedversion.clientVersionUpload) == "string"
            then
                version = decodedversion.clientVersionUpload
                cachestore.Write(versionpath, tostring(os.time()) .. "|" .. version)
            end
        end
    end

    if version then
        self.Version = version
    end

    local cachepath = "Explorer/api_" .. tostring(self.Version):gsub("[^%w%-_]", "_") .. ".json"
    local raw = cachestore.Read(cachepath)
    local fromcache = raw ~= nil

    if not raw and version then
        raw = cachestore.HttpGet("https://setup.rbxcdn.com/" .. version .. "-API-Dump.json")
    end

    if not raw then
        self.Error = "Unable to fetch Roblox API dump"
        return false
    end

    local ok, decoded = pcall(httpservice.JSONDecode, httpservice, raw)
    if not ok or type(decoded) ~= "table" then
        self.Error = "Unable to decode Roblox API dump"
        return false
    end

    if not fromcache then
        cachestore.Write(cachepath, raw)
    end

    local classes = {}
    for _, c in decoded.Classes or {} do
        local cls = {
            Name = c.Name,
            SuperclassName = c.Superclass,
            Tags = {},
            Properties = {},
        }

        for _, tag in c.Tags or {} do
            cls.Tags[tag] = true
        end

        for _, m in c.Members or {} do
            if m.MemberType == "Property" then
                local tags = {}
                for _, tag in m.Tags or {} do tags[tag] = true end

                local readsecurity = "None"
                local writesecurity = "None"

                if type(m.Security) == "table" then
                    readsecurity =
                        m.Security.Read
                        or m.Security.read
                        or "None"

                    writesecurity =
                        m.Security.Write
                        or m.Security.write
                        or "None"
                elseif type(m.Security) == "string" then
                    readsecurity = m.Security
                    writesecurity = m.Security
                end

                cls.Properties[#cls.Properties + 1] = {
                    Name = m.Name,
                    Category = runtimeutil.Trim(m.Category or "Other"),
                    ValueType = m.ValueType and m.ValueType.Name or "Variant",
                    ValueCategory = m.ValueType and m.ValueType.Category or nil,
                    ReadSecurity = readsecurity,
                    WriteSecurity = writesecurity,
                    Security = m.Security,
                    Tags = tags,
                    DeclaredClass = c.Name,
                }
            end
        end

        classes[cls.Name] = cls
    end

    for _, cls in classes do
        cls.Superclass = classes[cls.SuperclassName]
    end

    local enums = {}
    for _, e in decoded.Enums or {} do
        local items = {}
        for _, item in e.Items or {} do
            items[item.Name] = item.Value
        end
        enums[e.Name] = items
    end

    self.Classes = classes
    self.Enums = enums
    self.PropertyCache = {}

    pcall(function()
        self:LoadReflectionMetadata()
    end)

    self.Ready = true
    self.Error = nil
    return true
end

function metadataprovider:IsBrowsableProperty(p: any): boolean
    if not p or not p.Name then
        return false
    end

    local tags = p.Tags or {}

    if tags.Hidden
        or tags.Deprecated
        or tags.NotBrowsable
        or tags.WriteOnly
    then
        return false
    end

    local readsecurity = p.ReadSecurity or "None"
    if readsecurity ~= "None" then
        return false
    end

    return true
end

function metadataprovider:IsPropertyWritable(p: any): boolean
    if not p then
        return false
    end

    local tags = p.Tags or {}

    if tags.ReadOnly
        or tags.NotScriptable
        or tags.Hidden
        or tags.Deprecated
        or tags.NotBrowsable
    then
        return false
    end

    local writesecurity = p.WriteSecurity or "None"
    return writesecurity == "None"
end

function metadataprovider:GetProperties(classname: string): {any}?
    if not self.Ready then
        return nil
    end

    local cached = self.PropertyCache[classname]
    if cached then
        return cached
    end

    local chain = {}
    local cls = self.Classes[classname]

    while cls do
        table.insert(chain, 1, cls)
        cls = cls.Superclass
    end

    local byname = {}

    for _, c in chain do
        for _, p in c.Properties do
            byname[p.Name] = p
        end
    end

    local out = {}

    for _, p in byname do
        if self:IsBrowsableProperty(p) then
            out[#out + 1] = p
        end
    end

    table.sort(out, function(a, b)
        local ac = tostring(a.Category or "Other"):lower()
        local bc = tostring(b.Category or "Other"):lower()

        if ac == bc then
            return tostring(a.Name):lower() < tostring(b.Name):lower()
        end

        return ac < bc
    end)

    self.PropertyCache[classname] = out
    return out
end

local theme = {
    Bg = Color3.fromRGB(31, 31, 31),
    Panel = Color3.fromRGB(36, 36, 36),
    Panel2 = Color3.fromRGB(42, 42, 42),
    Panel3 = Color3.fromRGB(47, 47, 47),
    Hover = Color3.fromRGB(51, 55, 60),
    Selected = Color3.fromRGB(47, 83, 112),
    Border = Color3.fromRGB(62, 62, 62),
    BorderSoft = Color3.fromRGB(50, 50, 50),
    Text = Color3.fromRGB(226, 226, 226),
    Dim = Color3.fromRGB(155, 155, 155),
    Accent = Color3.fromRGB(88, 166, 255),
    Accent2 = Color3.fromRGB(115, 196, 255),
    Danger = Color3.fromRGB(210, 85, 85),
    Rail = Color3.fromRGB(32, 32, 32),
}

function uifactory.Create(class: string, props: {[string]: any}?, parent: Instance?): any
    local o = Instance.new(class)
    for k, v in props or {} do
        o[k] = v
    end
    if parent then o.Parent = parent end
    return o
end

function uifactory.Round(obj: GuiObject, px: number)
    uifactory.Create("UICorner", {CornerRadius = UDim.new(0, px or 5)}, obj)
end

function uifactory.Stroke(obj: GuiObject, color: Color3)
    uifactory.Create("UIStroke", {
        Color = color or theme.Border,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

function uifactory.Text(parent: Instance, text: string, size: number, align: Enum.TextXAlignment?): TextLabel
    return uifactory.Create("TextLabel", {
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = theme.Text,
        TextSize = size or 14,
        Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
        TextXAlignment = align or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        LineHeight = 1,
        BorderSizePixel = 0,
    }, parent)
end

function uifactory.Button(parent, text)
    local b = uifactory.Create("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        Text = text or "",
        TextColor3 = theme.Text,
        TextSize = 13,
        Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    }, parent)
    uifactory.Round(b, 4)
    return b
end

local parent = adapter:GetGuiParent()
assert(parent, "Explorer: no valid GUI parent")

local old = parent:FindFirstChild("Explorer")
if old then old:Destroy() end

local rootgui = uifactory.Create("ScreenGui", {
    Name = "Explorer",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, parent)

if adapter.protectgui then
    pcall(adapter.protectgui, rootgui)
end

local screenbounds = uifactory.Create("Frame", {
    Name = "_ScreenBounds",
    Size = UDim2.fromScale(1, 1),
    Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = false,
    ZIndex = 0,
}, rootgui)

local main = uifactory.Create("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(470, 690),
    Position = UDim2.new(1, -470, 0, 0),
    BackgroundColor3 = theme.Bg,
    BorderSizePixel = 0,
    Active = true,
    Selectable = false,
    ClipsDescendants = true,
}, rootgui)
uifactory.Stroke(main, theme.Border)

local mainsizeconstraint = uifactory.Create("UISizeConstraint", {
    MinSize = Vector2.new(390, 360),
    MaxSize = Vector2.new(1050, 100000),
}, main)

local dock: DockState = {
    Side = "Right",
    Docked = true,
    Width = 470,
    FloatingSize = Vector2.new(560, 690),
    FloatingPosition = nil,
    SnapDistance = 42,

    RespectGuiInset = false,

    TopGap = 0,
    BottomGap = 0,

    BottomOverscan = 0,
    Collapsed = false,
}

function dockcontroller.GetViewport(): Vector2

    local size = screenbounds.AbsoluteSize
    if size.X > 0 and size.Y > 0 then
        return size
    end

    local cam = workspace.CurrentCamera
    if cam then
        return cam.ViewportSize
    end

    return Vector2.new(1280, 720)
end

function dockcontroller.GetGuiInsets(): (Vector2, Vector2)
    local ok, topleft, bottomright = pcall(guiservice.GetGuiInset, guiservice)
    if ok then
        return topleft, bottomright
    end
    return Vector2.zero, Vector2.zero
end

function dockcontroller.ApplyRightDock()
    local viewport = dockcontroller.GetViewport()
    local width = runtimeutil.Clamp(dock.Width, 390, math.max(390, viewport.X - 120))

    main.AnchorPoint = Vector2.new(0, 0)

    if dock.RespectGuiInset then
        local topinset, bottominset = dockcontroller.GetGuiInsets()
        local top = topinset.Y + dock.TopGap
        local bottom = bottominset.Y + dock.BottomGap

        main.Position = UDim2.new(1, -width, 0, top)

        if dock.Collapsed then
            main.Size = UDim2.fromOffset(width, 28)
        else
            main.Size = UDim2.new(
                0, width,
                1, dock.BottomOverscan - top - bottom
            )
        end
    else
        main.Position = UDim2.new(1, -width, 0, dock.TopGap)

        if dock.Collapsed then
            main.Size = UDim2.fromOffset(width, 28)
        else
            main.Size = UDim2.new(
                0, width,
                1, dock.BottomOverscan - dock.TopGap - dock.BottomGap
            )
        end
    end
end

function dockcontroller.SaveFloatingGeometry()
    if not dock.Collapsed then
        dock.FloatingSize = Vector2.new(main.AbsoluteSize.X, main.AbsoluteSize.Y)
    end

    dock.FloatingPosition = Vector2.new(main.AbsolutePosition.X, main.AbsolutePosition.Y)
end

function dockcontroller.Undock(mouseposition: Vector2?)
    if not dock.Docked then return end

    dock.Docked = false
    local size = dock.FloatingSize or Vector2.new(560, 690)

    main.AnchorPoint = Vector2.zero

    if dock.Collapsed then
        main.Size = UDim2.fromOffset(size.X, 28)
    else
        main.Size = UDim2.fromOffset(size.X, size.Y)
    end

    local pos = dock.FloatingPosition
    if mouseposition then
        pos = Vector2.new(
            mouseposition.X - math.floor(size.X * 0.72),
            math.max(0, mouseposition.Y - 12)
        )
    end
    pos = pos or Vector2.new(200, 80)

    main.Position = UDim2.fromOffset(pos.X, pos.Y)
end

function dockcontroller.DockRight()
    if not dock.Docked then
        dockcontroller.SaveFloatingGeometry()
    end
    dock.Docked = true
    dock.Side = "Right"
    dock.Width = main.AbsoluteSize.X
    dockcontroller.ApplyRightDock()
end

function dockcontroller.ShouldSnapRight()
    local rightedge = screenbounds.AbsolutePosition.X + screenbounds.AbsoluteSize.X
    local mainright = main.AbsolutePosition.X + main.AbsoluteSize.X
    return math.abs(rightedge - mainright) <= dock.SnapDistance
end

local viewportconn
local cameraviewportconn

function dockcontroller.BindViewport()
    if viewportconn then
        viewportconn:Disconnect()
        viewportconn = nil
    end

    if cameraviewportconn then
        cameraviewportconn:Disconnect()
        cameraviewportconn = nil
    end

    viewportconn = screenbounds:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if dock.Docked then
            task.defer(dockcontroller.ApplyRightDock)
        end
    end)

    local cam = workspace.CurrentCamera
    if cam then
        cameraviewportconn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if dock.Docked then
                task.defer(dockcontroller.ApplyRightDock)
            end
        end)
    end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    dockcontroller.BindViewport()
    if dock.Docked then
        task.defer(dockcontroller.ApplyRightDock)
    end
end)

dockcontroller.BindViewport()
task.defer(function()
    runservice.RenderStepped:Wait()
    dockcontroller.ApplyRightDock()
end)

local topbar = uifactory.Create("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = Color3.fromRGB(34, 34, 34),
    BorderSizePixel = 0,
    Active = true,
}, main)

local title = uifactory.Text(topbar, "Explorer", 16)
title.Size = UDim2.new(1, -144, 1, 0)
title.Position = UDim2.fromOffset(8, 0)
title.TextColor3 = theme.Text
title.Font = Enum.Font.Code

local countlabel = uifactory.Text(topbar, "", 1)
countlabel.Visible = false
countlabel.Size = UDim2.fromOffset(0, 0)

local statuslabel = uifactory.Text(topbar, "", 1)
statuslabel.Visible = false
statuslabel.Size = UDim2.fromOffset(0, 0)

local topbuttons = uifactory.Create("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -140, 0, 0),
    Size = UDim2.fromOffset(140, 28),
}, topbar)

function dockcontroller.TitleButton(text, x, width)
    local b = uifactory.Create("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(x, 0),
        Size = UDim2.fromOffset(width or 26, 24),
        Text = text,
        TextColor3 = theme.Dim,
        TextSize = 13,
        Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    }, topbuttons)
    b.MouseEnter:Connect(function() b.BackgroundTransparency = 0; b.BackgroundColor3 = theme.Hover; b.TextColor3 = theme.Text end)
    b.MouseLeave:Connect(function() b.BackgroundTransparency = 1; b.TextColor3 = theme.Dim end)
    return b
end

local settings = uifactory.Create("ImageButton", {
    Name = "Settings",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(34, 34, 34),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(28, 0),
    Size = UDim2.fromOffset(28, 28),
    Image = "",
    ZIndex = topbuttons.ZIndex + 1,
}, topbuttons)

local settingsicon = uifactory.Create("ImageLabel", {
    Name = "Icon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(15, 15),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "rbxassetid://100616958975023",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = settings.ZIndex + 1,
}, settings)

settings.MouseEnter:Connect(function()
    settings.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    settingsicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

settings.MouseLeave:Connect(function()
    local active = settings:GetAttribute("Active") == true

    settings.BackgroundColor3 =
        active
        and Color3.fromRGB(50, 53, 59)
        or Color3.fromRGB(34, 34, 34)

    settingsicon.ImageColor3 =
        active
        and theme.Accent
        or Color3.fromRGB(235, 235, 235)
end)

local collapse = uifactory.Create("ImageButton", {
    Name = "Collapse",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(34, 34, 34),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(56, 0),
    Size = UDim2.fromOffset(28, 28),
    Image = "",
    ZIndex = topbuttons.ZIndex + 1,
}, topbuttons)

local collapseicon = uifactory.Create("ImageLabel", {
    Name = "Icon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(15, 15),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "rbxassetid://95761527892880",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = collapse.ZIndex + 1,
}, collapse)

collapse.MouseEnter:Connect(function()
    collapse.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    collapseicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

collapse.MouseLeave:Connect(function()
    collapse.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
    collapseicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
end)

local docktop = uifactory.Create("ImageButton", {
    Name = "DockTop",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(34, 34, 34),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(84, 0),
    Size = UDim2.fromOffset(28, 28),
    Image = "",
    ZIndex = topbuttons.ZIndex + 1,
}, topbuttons)

local dockicon = uifactory.Create("ImageLabel", {
    Name = "Icon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(15, 15),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "rbxassetid://103869391243035",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = docktop.ZIndex + 1,
}, docktop)

local close = uifactory.Create("ImageButton", {
    Name = "Close",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(34, 34, 34),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(112, 0),
    Size = UDim2.fromOffset(28, 28),
    Image = "",
    ZIndex = topbuttons.ZIndex + 1,
}, topbuttons)

local closeicon = uifactory.Create("ImageLabel", {
    Name = "Icon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(15, 15),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "rbxassetid://108916834720941",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = close.ZIndex + 1,
}, close)

docktop.MouseEnter:Connect(function()
    docktop.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    dockicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

docktop.MouseLeave:Connect(function()
    docktop.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
    dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
end)

close.MouseEnter:Connect(function()
    close.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    closeicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

close.MouseLeave:Connect(function()
    close.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
    closeicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
end)

local bodyui = uifactory.Create("Frame", {
    Name = "Body",
    Position = UDim2.fromOffset(0, 28),
    Size = UDim2.new(1, 0, 1, -28),
    BackgroundColor3 = theme.Bg,
    BorderSizePixel = 0,
}, main)

local loadingoverlay = uifactory.Create("Frame", {
    Name = "LoadingOverlay",
    Position = UDim2.fromOffset(0, 28),
    Size = UDim2.new(1, 0, 1, -28),
    BackgroundColor3 = theme.Bg,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 80,
}, main)

local loadingstatus = uifactory.Text(loadingoverlay, "Starting Explorer...", 16, Enum.TextXAlignment.Center)
loadingstatus.AnchorPoint = Vector2.new(0.5, 1)
loadingstatus.Position = UDim2.new(0.5, 0, 0.5, -6)
loadingstatus.Size = UDim2.fromOffset(360, 24)
loadingstatus.TextColor3 = Color3.fromRGB(220, 220, 220)
loadingstatus.TextTruncate = Enum.TextTruncate.AtEnd
loadingstatus.ZIndex = 82

local loadingshimmer = uifactory.Create("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(180, 180, 180)),
        ColorSequenceKeypoint.new(0.38, Color3.fromRGB(215, 215, 215)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.62, Color3.fromRGB(215, 215, 215)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(180, 180, 180)),
    }),
    Offset = Vector2.new(-1, 0),
}, loadingstatus)

task.spawn(function()
    while loadingoverlay and loadingoverlay.Parent do
        if loadingoverlay.Visible then
            loadingshimmer.Offset =
                Vector2.new(
                    ((os.clock() * 0.75) % 2) - 1,
                    0
                )

            runservice.RenderStepped:Wait()
        else
            task.wait(0.08)
        end
    end
end)

local loadingtrack = uifactory.Create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(220, 8),
    BackgroundColor3 = Color3.fromRGB(49, 49, 49),
    BorderSizePixel = 0,
    ZIndex = 82,
}, loadingoverlay)
uifactory.Round(loadingtrack, 4)

local loadingfill = uifactory.Create("Frame", {
    Size = UDim2.fromScale(0, 1),
    BackgroundColor3 = theme.Accent,
    BorderSizePixel = 0,
    ZIndex = 83,
}, loadingtrack)
uifactory.Round(loadingfill, 4)

local loadingcount = uifactory.Text(loadingoverlay, "", 1, Enum.TextXAlignment.Center)
loadingcount.Visible = false
loadingcount.Size = UDim2.fromOffset(0, 0)

local loadingdetail = uifactory.Text(loadingoverlay, "", 1, Enum.TextXAlignment.Center)
loadingdetail.Visible = false
loadingdetail.Size = UDim2.fromOffset(0, 0)

function loadingcontroller.SetProgress(done, total, detail)
    done = tonumber(done) or 0
    total = tonumber(total) or 0

    local ratio =
        total > 0
        and math.clamp(done / total, 0, 1)
        or 0

    loadingfill.Size = UDim2.fromScale(ratio, 1)
    loadingstatus.Text =
        tostring(detail or "Loading...")
end

function loadingcontroller.SetStage(percent, detail, counttext)
    local ratio =
        math.clamp(
            (tonumber(percent) or 0) / 100,
            0,
            1
        )

    loadingfill.Size = UDim2.fromScale(ratio, 1)
    loadingstatus.Text =
        tostring(detail or "Loading...")
end

function loadingcontroller.SetIconProgress(done, total, detail)
    done = tonumber(done) or 0
    total = tonumber(total) or 0

    local iconratio = total > 0 and math.clamp(done / total, 0, 1) or 0
    local overall = 25 + iconratio * 70

    loadingcontroller.SetStage(
        overall,
        detail,
        total > 0 and ("%d / %d icons"):format(done, total) or "icons"
    )
end

local splitratio = 0.64

local explorerpane = uifactory.Create("Frame", {
    Name = "ExplorerPane",
    BackgroundColor3 = theme.Panel,
    BorderSizePixel = 0,
}, bodyui)
uifactory.Stroke(explorerpane, theme.BorderSoft)

local search = uifactory.Create("TextBox", {
    Position = UDim2.fromOffset(4, 4),
    Size = UDim2.new(1, -8, 0, 28),
    BackgroundColor3 = Color3.fromRGB(29, 29, 29),
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    PlaceholderText = "Filter Workspace...",
    PlaceholderColor3 = Color3.fromRGB(125, 125, 125),
    Text = "",
    TextColor3 = theme.Text,
    TextSize = 16,
    Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    TextXAlignment = Enum.TextXAlignment.Left,
}, explorerpane)
uifactory.Stroke(search, theme.BorderSoft)
uifactory.Create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, search)

local treescroll = uifactory.Create("ScrollingFrame", {
    Position = UDim2.fromOffset(2, 36),
    Size = UDim2.new(1, -4, 1, -38),
    BackgroundColor3 = theme.Panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 7,
    ScrollBarImageColor3 = Color3.fromRGB(92, 92, 92),
    CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, explorerpane)

local splitter = uifactory.Create("TextButton", {
    Name = "PaneSplitter",
    AutoButtonColor = false,
    Text = "",
    BackgroundColor3 = theme.Border,
    BorderSizePixel = 0,
    Active = true,
}, bodyui)

local propertiespane = uifactory.Create("Frame", {
    Name = "PropertiesPane",
    BackgroundColor3 = theme.Panel,
    BorderSizePixel = 0,
}, bodyui)
uifactory.Stroke(propertiespane, theme.BorderSoft)

local propertiesheader = uifactory.Create("Frame", {
    Size = UDim2.new(1, 0, 0, 28),
    BackgroundColor3 = theme.Panel2,
    BorderSizePixel = 0,
}, propertiespane)

local righttitle = uifactory.Text(propertiesheader, "Properties", 16)
righttitle.Position = UDim2.fromOffset(6, 0)
righttitle.Size = UDim2.new(0, 95, 1, 0)
righttitle.TextColor3 = theme.Text

local propsearch = uifactory.Create("TextBox", {
    Position = UDim2.fromOffset(4, 32),
    Size = UDim2.new(1, -8, 0, 28),
    BackgroundColor3 = Color3.fromRGB(29, 29, 29),
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    PlaceholderText = "Search Properties",
    PlaceholderColor3 = Color3.fromRGB(125, 125, 125),
    Text = "",
    TextColor3 = theme.Text,
    TextSize = 16,
    Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    TextXAlignment = Enum.TextXAlignment.Left,
}, propertiespane)
uifactory.Stroke(propsearch, theme.BorderSoft)
uifactory.Create("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, propsearch)

local propscroll = uifactory.Create("ScrollingFrame", {
    Position = UDim2.fromOffset(2, 61),
    Size = UDim2.new(1, -4, 1, -63),
    BackgroundColor3 = theme.Panel,
    BorderSizePixel = 0,
    ScrollBarThickness = 7,
    ScrollBarImageColor3 = Color3.fromRGB(92, 92, 92),
    CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.XY,
    ElasticBehavior = Enum.ElasticBehavior.Never,
}, propertiespane)

local propertydropdown = uifactory.Create("Frame", {
    Name = "PropertyDropdown",
    Visible = false,
    BackgroundColor3 = Color3.fromRGB(31, 31, 31),
    BorderSizePixel = 0,
    ZIndex = 50,
    ClipsDescendants = true,
}, propertiespane)
uifactory.Stroke(propertydropdown, theme.Border)

local propertydropdownscroll = uifactory.Create("ScrollingFrame", {
    Position = UDim2.fromOffset(1, 1),
    Size = UDim2.new(1, -2, 1, -2),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 6,
    ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100),
    CanvasSize = UDim2.new(),
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ZIndex = 51,
}, propertydropdown)

local propertydropdownstate = {
    Frame = propertydropdown,
    Scroll = propertydropdownscroll,
    ActiveRow = nil,
}

local prop_canvas_min_w = 0
local prop_name_w = 190

function propertycontroller.GetCanvasWidth(): number
    return math.max(
        prop_canvas_min_w,
        math.floor(propscroll.AbsoluteSize.X - propscroll.ScrollBarThickness - 2)
    )
end

function propertycontroller.GetViewportWidth(): number
    return math.max(
        prop_name_w + 90,
        math.floor(propscroll.AbsoluteSize.X - propscroll.ScrollBarThickness - 2)
    )
end

function propertycontroller.GetVisibleRight(): number
    return propscroll.CanvasPosition.X + propertycontroller.GetViewportWidth()
end

function layoutcontroller.UpdateSplit()
    local s = runtimeutil.Clamp(splitratio, 0.28, 0.78)
    explorerpane.Position = UDim2.fromOffset(0, 0)
    explorerpane.Size = UDim2.new(1, 0, s, -3)
    splitter.Position = UDim2.new(0, 0, s, -3)
    splitter.Size = UDim2.new(1, 0, 0, 6)
    propertiespane.Position = UDim2.new(0, 0, s, 3)
    propertiespane.Size = UDim2.new(1, 0, 1 - s, -3)
end
layoutcontroller.UpdateSplit()

do
    local dragging = false
    splitter.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            splitter.BackgroundColor3 = theme.Accent
        end
    end)
    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false
            splitter.BackgroundColor3 = theme.Border
        end
    end)
    uis.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local bodyy = bodyui.AbsolutePosition.Y
            local h = math.max(1, bodyui.AbsoluteSize.Y)
            splitratio = runtimeutil.Clamp((input.Position.Y - bodyy) / h, 0.28, 0.78)
            layoutcontroller.UpdateSplit()
        end
    end)
end

do
    local dragging = false
    local dragstart, startpos
    local starteddocked = false

    topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragstart = input.Position
            startpos = main.Position
            starteddocked = dock.Docked
        end
    end)

    uis.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragstart

            if dock.Docked then

                if d.X < -28 then
                    dockcontroller.Undock(input.Position)
                    dragstart = input.Position
                    startpos = main.Position
                else
                    return
                end
            end

            main.Position = UDim2.new(
                startpos.X.Scale, startpos.X.Offset + (input.Position.X - dragstart.X),
                startpos.Y.Scale, startpos.Y.Offset + (input.Position.Y - dragstart.Y)
            )
        end
    end)

    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
            dragging = false

            if not dock.Docked and dockcontroller.ShouldSnapRight() then
                dockcontroller.DockRight()
                dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
                statuslabel.Text = "Docked to right"
            elseif not dock.Docked then
                dockcontroller.SaveFloatingGeometry()
                dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
            end
        end
    end)
end

local resizegrip = uifactory.Create("TextButton", {
    Name = "ResizeGrip",
    AutoButtonColor = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -16, 1, -16),
    Size = UDim2.fromOffset(16, 16),
    Text = "◢",
    TextColor3 = theme.Dim,
    TextSize = 12,
    Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    ZIndex = 20,
}, main)

local dockresize = uifactory.Create("TextButton", {
    Name = "DockResize",
    AutoButtonColor = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(0, 5, 1, 0),
    Text = "",
    ZIndex = 25,
}, main)

dockresize.MouseEnter:Connect(function()
    if dock.Docked then
        dockresize.BackgroundTransparency = 0
        dockresize.BackgroundColor3 = theme.Accent
    end
end)
dockresize.MouseLeave:Connect(function()
    dockresize.BackgroundTransparency = 1
end)

do
    local resizing = false
    local startmouse, startsize

    resizegrip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            and not dock.Docked
            and not dock.Collapsed
        then
            resizing = true
            startmouse = input.Position
            startsize = main.AbsoluteSize
        end
    end)

    uis.InputChanged:Connect(function(input)
        if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startmouse
            local w = runtimeutil.Clamp(startsize.X + d.X, 390, 1050)
            local h = runtimeutil.Clamp(startsize.Y + d.Y, 360, 1400)
            main.Size = UDim2.fromOffset(w, h)
        end
    end)

    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and resizing then
            resizing = false
            dockcontroller.SaveFloatingGeometry()
        end
    end)
end

do
    local resizing = false
    local startx, startwidth

    dockresize.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and dock.Docked then
            resizing = true
            startx = input.Position.X
            startwidth = main.AbsoluteSize.X
        end
    end)

    uis.InputChanged:Connect(function(input)
        if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = startx - input.Position.X
            dock.Width = runtimeutil.Clamp(startwidth + delta, 390, 820)
            dockcontroller.ApplyRightDock()
        end
    end)

    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = false
        end
    end)
end

function dockcontroller.SetCollapsed(collapsed: boolean)
    collapsed = collapsed == true

    if dock.Collapsed == collapsed then
        return
    end

    if collapsed and not dock.Docked then
        dock.FloatingSize = Vector2.new(
            main.AbsoluteSize.X,
            math.max(360, main.AbsoluteSize.Y)
        )
        dock.FloatingPosition = Vector2.new(
            main.AbsolutePosition.X,
            main.AbsolutePosition.Y
        )
    end

    dock.Collapsed = collapsed
    mainsizeconstraint.MinSize =
        collapsed
        and Vector2.new(390, 28)
        or Vector2.new(390, 360)

    collapseicon.Rotation = collapsed and 180 or 0

    if dock.Docked then
        dockcontroller.ApplyRightDock()
    else
        local size = dock.FloatingSize or Vector2.new(560, 690)

        if collapsed then
            main.Size = UDim2.fromOffset(
                main.AbsoluteSize.X,
                28
            )
        else
            main.Size = UDim2.fromOffset(
                size.X,
                size.Y
            )
        end
    end

    resizegrip.Visible =
        not collapsed
        and not dock.Docked

    dockresize.Visible =
        dock.Docked
end

collapse.MouseButton1Click:Connect(function()
    dockcontroller.SetCollapsed(not dock.Collapsed)
end)

close.MouseButton1Click:Connect(function()
    rootgui:Destroy()
end)

docktop.MouseButton1Click:Connect(function()
    if dock.Docked then
        dockcontroller.Undock()
        dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
        resizegrip.Visible = not dock.Collapsed
        dockresize.Visible = false
        statuslabel.Text = "Floating window"
    else
        dockcontroller.DockRight()
        dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
        resizegrip.Visible = false
        dockresize.Visible = true
        statuslabel.Text = "Docked to right"
    end
end)

dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
resizegrip.Visible = false
dockresize.Visible = true
collapseicon.Rotation = dock.Collapsed and 180 or 0

local toolactions = {
    Refresh = nil,
    ViewScript = nil,
}

toolactions.PropertyDropdownState = propertydropdownstate

local selectednode: ExplorerNode?

toolactions.Selection = {
    Set = {},
    List = {},
    Anchor = nil,
}

toolactions.ViewerUI = {}

toolactions.ViewerUI.Overlay = uifactory.Create("Frame", {
    Name = "ScriptViewerOverlay",
    Visible = false,
    Active = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    ZIndex = 500,
}, rootgui)

toolactions.ViewerUI.Window = uifactory.Create("Frame", {
    Name = "ScriptViewerWindow",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(760, 520),
    BackgroundColor3 = Color3.fromRGB(26, 27, 30),
    BorderSizePixel = 0,
    Active = true,
    ClipsDescendants = true,
    ZIndex = 501,
}, toolactions.ViewerUI.Overlay)
uifactory.Round(toolactions.ViewerUI.Window, 5)
uifactory.Stroke(toolactions.ViewerUI.Window, Color3.fromRGB(65, 68, 75))

uifactory.Create("UISizeConstraint", {
    MinSize = Vector2.new(430, 300),
    MaxSize = Vector2.new(1200, 900),
}, toolactions.ViewerUI.Window)

toolactions.ViewerUI.Top = uifactory.Create("Frame", {
    Name = "TitleBar",
    Size = UDim2.new(1, 0, 0, 32),
    BackgroundColor3 = Color3.fromRGB(31, 33, 37),
    BorderSizePixel = 0,
    Active = true,
    ZIndex = 502,
}, toolactions.ViewerUI.Window)

toolactions.ViewerUI.Title = uifactory.Text(
    toolactions.ViewerUI.Top,
    "Script Viewer",
    15
)
toolactions.ViewerUI.Title.Position = UDim2.fromOffset(10, 0)
toolactions.ViewerUI.Title.Size = UDim2.new(1, -54, 1, 0)
toolactions.ViewerUI.Title.TextColor3 = theme.Text
toolactions.ViewerUI.Title.TextTruncate = Enum.TextTruncate.AtEnd
toolactions.ViewerUI.Title.ZIndex = 503

toolactions.ViewerUI.Close = uifactory.Create("ImageButton", {
    Name = "Close",
    AutoButtonColor = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -32, 0, 2),
    Size = UDim2.fromOffset(28, 28),
    Image = "",
    ZIndex = 503,
}, toolactions.ViewerUI.Top)

toolactions.ViewerUI.CloseIcon = uifactory.Create("ImageLabel", {
    Name = "Icon",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(18, 18),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Image = "rbxassetid://108916834720941",
    ImageColor3 = Color3.fromRGB(220, 220, 220),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = 504,
}, toolactions.ViewerUI.Close)

toolactions.ViewerUI.Close.MouseEnter:Connect(function()
    toolactions.ViewerUI.Close.BackgroundTransparency = 0
    toolactions.ViewerUI.Close.BackgroundColor3 = Color3.fromRGB(52, 54, 60)
    toolactions.ViewerUI.CloseIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

toolactions.ViewerUI.Close.MouseLeave:Connect(function()
    toolactions.ViewerUI.Close.BackgroundTransparency = 1
    toolactions.ViewerUI.CloseIcon.ImageColor3 = Color3.fromRGB(220, 220, 220)
end)

toolactions.ViewerUI.Toolbar = uifactory.Create("Frame", {
    Name = "ScriptToolbar",
    Position = UDim2.fromOffset(8, 34),
    Size = UDim2.new(1, -16, 0, 22),
    BackgroundColor3 = Color3.fromRGB(31, 33, 37),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    ZIndex = 502,
}, toolactions.ViewerUI.Window)

function viewercontroller.CreateToolbarButton(name, textvalue, position, size)
    local button = uifactory.Create("TextButton", {
        Name = name,
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
        Text = textvalue,
        TextColor3 = Color3.fromRGB(235, 235, 235),
        TextSize = 13,
        Font = Enum.Font.SourceSans,
        ZIndex = 503,
    }, toolactions.ViewerUI.Toolbar)

    button.MouseEnter:Connect(function()
        button.BackgroundTransparency = 0
        button.BackgroundColor3 = Color3.fromRGB(49, 51, 56)
        button.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)

    button.MouseLeave:Connect(function()
        button.BackgroundTransparency = 1
        button.TextColor3 = Color3.fromRGB(235, 235, 235)
    end)

    return button
end

toolactions.ViewerUI.CopyButton = viewercontroller.CreateToolbarButton(
    "CopyToClipboard",
    "Copy to Clipboard",
    UDim2.new(0, 0, 0, 0),
    UDim2.new(0.35, 0, 1, 0)
)

toolactions.ViewerUI.SaveButton = viewercontroller.CreateToolbarButton(
    "SaveToFile",
    "Save to File",
    UDim2.new(0.35, 0, 0, 0),
    UDim2.new(0.30, 0, 1, 0)
)

toolactions.ViewerUI.DumpButton = viewercontroller.CreateToolbarButton(
    "DumpFunctions",
    "Dump Functions",
    UDim2.new(0.65, 0, 0, 0),
    UDim2.new(0.35, 0, 1, 0)
)

toolactions.ViewerUI.CodeFrame = uifactory.Create("Frame", {
    Position = UDim2.fromOffset(8, 58),
    Size = UDim2.new(1, -16, 1, -66),
    BackgroundColor3 = Color3.fromRGB(37, 37, 37),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 502,
}, toolactions.ViewerUI.Window)
uifactory.Round(toolactions.ViewerUI.CodeFrame, 4)

toolactions.ViewerUI.Scroll = uifactory.Create("ScrollingFrame", {
    Name = "CodeScroll",
    Position = UDim2.fromOffset(6, 6),
    Size = UDim2.new(1, -12, 1, -12),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    CanvasSize = UDim2.fromOffset(0, 0),
    ScrollingDirection = Enum.ScrollingDirection.XY,
    ScrollBarThickness = 8,
    ScrollBarImageColor3 = Color3.fromRGB(78, 82, 90),
    ElasticBehavior = Enum.ElasticBehavior.Never,
    ZIndex = 503,
}, toolactions.ViewerUI.CodeFrame)

toolactions.ViewerUI.SourceLines = {}
toolactions.ViewerUI.LinePool = {}
toolactions.ViewerUI.LineHeight = 20
toolactions.ViewerUI.LinePoolSize = 58
toolactions.ViewerUI.LastFirstLine = -1
toolactions.ViewerUI.MaxLineLength = 0
toolactions.ViewerUI.RequestId = 0
toolactions.ViewerUI.SelectionLazyLimit = 300000
toolactions.ViewerUI.SelectionSource = ""
toolactions.ViewerUI.SelectionLoaded = false
toolactions.ViewerUI.RestoringSelectionText = false

toolactions.ViewerUI.SelectionBox = uifactory.Create("TextBox", {
    Name = "SelectionLayer",
    Position = UDim2.fromOffset(8, 0),
    Size = UDim2.fromOffset(100, 100),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ClearTextOnFocus = false,
    MultiLine = true,
    TextEditable = true,
    TextWrapped = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextColor3 = Color3.fromRGB(204, 204, 204),
    TextTransparency = 1,
    TextStrokeTransparency = 1,
    TextSize = 15,
    Font = Enum.Font.Code,
    LineHeight = 1.3333333333,
    Text = "",
    ZIndex = 505,
}, toolactions.ViewerUI.Scroll)

toolactions.ViewerUI.SelectionBox.Focused:Connect(function()
    if not toolactions.ViewerUI.SelectionLoaded then
        toolactions.ViewerUI.RestoringSelectionText = true
        toolactions.ViewerUI.SelectionBox.Text =
            toolactions.ViewerUI.SelectionSource or ""
        toolactions.ViewerUI.RestoringSelectionText = false

        toolactions.ViewerUI.SelectionLoaded = true
    end
end)

toolactions.ViewerUI.SelectionBox:GetPropertyChangedSignal("Text"):Connect(function()
    if toolactions.ViewerUI.RestoringSelectionText then
        return
    end

    local expected = toolactions.ViewerUI.SelectionSource or ""

    if toolactions.ViewerUI.SelectionBox.Text ~= expected then
        local cursor = toolactions.ViewerUI.SelectionBox.CursorPosition
        local selection = toolactions.ViewerUI.SelectionBox.SelectionStart

        toolactions.ViewerUI.RestoringSelectionText = true
        toolactions.ViewerUI.SelectionBox.Text = expected
        toolactions.ViewerUI.RestoringSelectionText = false

        pcall(function()
            toolactions.ViewerUI.SelectionBox.CursorPosition = cursor
            toolactions.ViewerUI.SelectionBox.SelectionStart = selection
        end)
    end
end)

toolactions.ViewerUI.SyntaxKeywords = {
    ["and"] = true,
    ["break"] = true,
    ["continue"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["export"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["type"] = true,
    ["until"] = true,
    ["while"] = true,
}

toolactions.ViewerUI.SyntaxLiterals = {
    ["true"] = true,
    ["false"] = true,
    ["nil"] = true,
}

toolactions.ViewerUI.SyntaxBuiltins = {
    ["assert"] = true,
    ["error"] = true,
    ["getfenv"] = true,
    ["getmetatable"] = true,
    ["ipairs"] = true,
    ["loadstring"] = true,
    ["next"] = true,
    ["pairs"] = true,
    ["pcall"] = true,
    ["print"] = true,
    ["rawequal"] = true,
    ["rawget"] = true,
    ["rawset"] = true,
    ["require"] = true,
    ["select"] = true,
    ["setfenv"] = true,
    ["setmetatable"] = true,
    ["tonumber"] = true,
    ["tostring"] = true,
    ["type"] = true,
    ["typeof"] = true,
    ["unpack"] = true,
    ["warn"] = true,
    ["xpcall"] = true,
    ["game"] = true,
    ["workspace"] = true,
    ["script"] = true,
    ["Enum"] = true,
    ["Instance"] = true,
    ["Vector2"] = true,
    ["Vector3"] = true,
    ["CFrame"] = true,
    ["Color3"] = true,
    ["UDim"] = true,
    ["UDim2"] = true,
    ["Ray"] = true,
    ["Rect"] = true,
    ["Region3"] = true,
    ["TweenInfo"] = true,
    ["task"] = true,
    ["math"] = true,
    ["string"] = true,
    ["table"] = true,
    ["coroutine"] = true,
    ["utf8"] = true,
    ["os"] = true,
    ["debug"] = true,
}

toolactions.ViewerUI.EscapeRichText = function(value)
    return tostring(value)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

toolactions.ViewerUI.ColorToken = function(value, color)
    return '<font color="' .. color .. '">'
        .. toolactions.ViewerUI.EscapeRichText(value)
        .. "</font>"
end

toolactions.ViewerUI.HighlightLine = function(line)

    if #line > 3500 then
        return toolactions.ViewerUI.EscapeRichText(line)
    end

    local out = {}
    local i = 1
    local n = #line
    local previousword = nil
    local previousnonspace = nil
    local expectfunctionname = false

    while i <= n do
        local c = line:sub(i, i)
        local n2 = i < n and line:sub(i + 1, i + 1) or ""

        if c == "-" and n2 == "-" then
            out[#out + 1] = toolactions.ViewerUI.ColorToken(
                line:sub(i),
                "#666666"
            )
            break
        end

        if c == '"' or c == "'" then
            local quote = c
            local j = i + 1
            local escaped = false

            while j <= n do
                local ch = line:sub(j, j)

                if escaped then
                    escaped = false
                elseif ch == "\\" then
                    escaped = true
                elseif ch == quote then
                    j += 1
                    break
                end

                j += 1
            end

            out[#out + 1] = toolactions.ViewerUI.ColorToken(
                line:sub(i, math.min(j - 1, n)),
                "#ADF195"
            )

            previousnonspace = quote
            i = j
            continue
        end

        if c:match("[%a_]") then
            local j = i + 1

            while j <= n and line:sub(j, j):match("[%w_]") do
                j += 1
            end

            local word = line:sub(i, j - 1)
            local nextchar = line:sub(j):match("^%s*(.)") or ""

            if toolactions.ViewerUI.SyntaxLiterals[word] then
                out[#out + 1] = toolactions.ViewerUI.ColorToken(
                    word,
                    "#FFC600"
                )
            elseif expectfunctionname then
                out[#out + 1] = toolactions.ViewerUI.ColorToken(
                    word,
                    "#FDFBAC"
                )
                expectfunctionname = false
            elseif previousnonspace == "." or previousnonspace == ":" then

                local color = nextchar == "(" and "#FDFBAC" or "#61A1F1"
                out[#out + 1] = toolactions.ViewerUI.ColorToken(
                    word,
                    color
                )
            elseif toolactions.ViewerUI.SyntaxKeywords[word] then
                out[#out + 1] = toolactions.ViewerUI.ColorToken(
                    word,
                    "#F86D7C"
                )

                if word == "function" then
                    expectfunctionname = true
                end
            elseif toolactions.ViewerUI.SyntaxBuiltins[word] then
                out[#out + 1] = toolactions.ViewerUI.ColorToken(
                    word,
                    "#84D6F7"
                )
            elseif nextchar == "(" and previousword ~= "if"
                and previousword ~= "while"
                and previousword ~= "for"
                and previousword ~= "return"
            then

                out[#out + 1] = toolactions.ViewerUI.ColorToken(
                    word,
                    "#FDFBAC"
                )
            else
                out[#out + 1] = toolactions.ViewerUI.EscapeRichText(word)
            end

            previousword = word
            previousnonspace = word
            i = j
            continue
        end

        if c:match("%d") then
            local j = i + 1

            while j <= n and line:sub(j, j):match("[%w%.xX_%-+]") do
                j += 1
            end

            out[#out + 1] = toolactions.ViewerUI.ColorToken(
                line:sub(i, j - 1),
                "#FFC600"
            )

            previousnonspace = "#"
            i = j
            continue
        end

        out[#out + 1] = toolactions.ViewerUI.EscapeRichText(c)

        if not c:match("%s") then
            previousnonspace = c
        end

        i += 1
    end

    return table.concat(out)
end

toolactions.ViewerUI.UpdateCanvas = function()
    local scroll = toolactions.ViewerUI.Scroll
    local linecount = #toolactions.ViewerUI.SourceLines

    local charwidth = 8
    pcall(function()
        charwidth = math.max(
            7,
            textservice:GetTextSize(
                "M",
                15,
                Enum.Font.Code,
                Vector2.new(100, 100)
            ).X
        )
    end)

    local contentwidth = math.max(
        scroll.AbsoluteSize.X - 2,
        16 + toolactions.ViewerUI.MaxLineLength * charwidth
    )

    local contentheight = math.max(
        scroll.AbsoluteSize.Y,
        linecount * toolactions.ViewerUI.LineHeight + 8
    )

    scroll.CanvasSize = UDim2.fromOffset(
        contentwidth,
        contentheight
    )

    toolactions.ViewerUI.SelectionBox.Position = UDim2.fromOffset(8, 0)
    toolactions.ViewerUI.SelectionBox.Size = UDim2.fromOffset(
        math.max(1, contentwidth - 16),
        math.max(1, contentheight)
    )
end

toolactions.ViewerUI.RenderLines = function(force)
    local scroll = toolactions.ViewerUI.Scroll
    local first = math.max(
        1,
        math.floor(scroll.CanvasPosition.Y / toolactions.ViewerUI.LineHeight) + 1
    )

    if not force and first == toolactions.ViewerUI.LastFirstLine then
        return
    end

    toolactions.ViewerUI.LastFirstLine = first

    local canvaswidth = math.max(
        scroll.CanvasSize.X.Offset,
        scroll.AbsoluteSize.X
    )

    for poolindex, label in toolactions.ViewerUI.LinePool do
        local lineindex = first + poolindex - 1
        local line = toolactions.ViewerUI.SourceLines[lineindex]

        if line ~= nil then
            label.Visible = true
            label.Position = UDim2.fromOffset(
                8,
                (lineindex - 1) * toolactions.ViewerUI.LineHeight
            )
            label.Size = UDim2.fromOffset(
                math.max(1, canvaswidth - 16),
                toolactions.ViewerUI.LineHeight
            )
            label.Text = toolactions.ViewerUI.HighlightLine(line)
        else
            label.Visible = false
            label.Text = ""
        end
    end
end

toolactions.ViewerUI.CurrentObject = nil
toolactions.ViewerUI.CurrentSource = ""
toolactions.ViewerUI.CurrentDump = ""
toolactions.ViewerUI.DisplayedText = ""
toolactions.ViewerUI.ShowingDump = false

toolactions.ViewerUI.ValuePreview = function(value)
    local kind = typeof(value)

    if kind == "string" then
        local s = value
        if #s > 300 then
            s = s:sub(1, 300) .. "...<truncated>"
        end
        return string.format("%q", s)
    elseif kind == "Instance" then
        local ok, path = pcall(function()
            return value:GetFullName()
        end)
        return ok and ("<" .. value.ClassName .. "> " .. path) or tostring(value)
    elseif kind == "table" then
        local count = 0
        pcall(function()
            for _ in value do
                count += 1
                if count >= 999 then break end
            end
        end)
        return ("table (%d items)"):format(count)
    end

    local ok, result = pcall(tostring, value)
    return ok and result or ("<" .. kind .. ">")
end

toolactions.ViewerUI.GetScriptClosure = function(obj)
    local candidates = {}

    if type(getscriptclosure) == "function" then
        candidates[#candidates + 1] = getscriptclosure
    end
    if type(getscriptfunction) == "function" then
        candidates[#candidates + 1] = getscriptfunction
    end

    for _, getter in candidates do
        local ok, closure = pcall(getter, obj)
        if ok and type(closure) == "function" then
            return closure
        end
    end

    return nil, "getscriptclosure/getscriptfunction is unavailable for this script"
end

toolactions.ViewerUI.DebugArray = function(kind, fn)
    local candidates = {}

    if type(debug) == "table" then
        if kind == "constants" and type(debug.getconstants) == "function" then
            candidates[#candidates + 1] = debug.getconstants
        elseif kind == "upvalues" and type(debug.getupvalues) == "function" then
            candidates[#candidates + 1] = debug.getupvalues
        elseif kind == "protos" and type(debug.getprotos) == "function" then
            candidates[#candidates + 1] = debug.getprotos
        end
    end

    if kind == "constants" and type(getconstants) == "function" then
        candidates[#candidates + 1] = getconstants
    elseif kind == "upvalues" and type(getupvalues) == "function" then
        candidates[#candidates + 1] = getupvalues
    elseif kind == "protos" and type(getprotos) == "function" then
        candidates[#candidates + 1] = getprotos
    end

    for _, getter in candidates do
        local ok, result = pcall(getter, fn)
        if ok and type(result) == "table" then
            return result
        end
    end

    return {}
end

toolactions.ViewerUI.FunctionInfo = function(fn)
    if type(debug) == "table" and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, fn)
        if ok and type(info) == "table" then
            return info
        end
    end

    if type(getinfo) == "function" then
        local ok, info = pcall(getinfo, fn)
        if ok and type(info) == "table" then
            return info
        end
    end

    return {}
end

toolactions.ViewerUI.BuildFunctionDump = function(rootfn, objectpath)
    local lines = {
        "-- Explorer Function Dump",
        "-- Script: " .. tostring(objectpath or "unknown"),
        "",
    }

    local seen = {}
    local dumpedfunctions = 0
    local max_functions = 80
    local max_depth = 3
    local max_items = 250

    local function add(indent, value)
        lines[#lines + 1] = string.rep("    ", indent) .. value
    end

    local function dumpfunction(fn, depth, label)
        if type(fn) ~= "function" or seen[fn] then
            return
        end

        if dumpedfunctions >= max_functions then
            add(depth, "-- function limit reached")
            return
        end

        seen[fn] = true
        dumpedfunctions += 1

        local info = toolactions.ViewerUI.FunctionInfo(fn)

        add(depth, ("function %s"):format(label or ("proto_" .. dumpedfunctions)))
        add(depth, ("address = %s"):format(tostring(fn)))

        if info.name then
            add(depth, "name = " .. toolactions.ViewerUI.ValuePreview(info.name))
        end
        if info.source or info.short_src then
            add(depth, "source = " .. toolactions.ViewerUI.ValuePreview(info.source or info.short_src))
        end
        if info.linedefined then
            add(depth, "line = " .. tostring(info.linedefined))
        end
        if info.nparams then
            add(depth, "params = " .. tostring(info.nparams))
        end

        local constants = toolactions.ViewerUI.DebugArray("constants", fn)
        if next(constants) ~= nil then
            add(depth, "constants:")
            local count = 0
            for index, value in constants do
                count += 1
                if count > max_items then
                    add(depth + 1, "-- constants truncated")
                    break
                end
                add(
                    depth + 1,
                    ("[%s] = %s"):format(
                        tostring(index),
                        toolactions.ViewerUI.ValuePreview(value)
                    )
                )
            end
        end

        local upvalues = toolactions.ViewerUI.DebugArray("upvalues", fn)
        if next(upvalues) ~= nil then
            add(depth, "upvalues:")
            local count = 0
            for index, value in upvalues do
                count += 1
                if count > max_items then
                    add(depth + 1, "-- upvalues truncated")
                    break
                end
                add(
                    depth + 1,
                    ("[%s] = %s"):format(
                        tostring(index),
                        toolactions.ViewerUI.ValuePreview(value)
                    )
                )
            end
        end

        if depth < max_depth then
            local protos = toolactions.ViewerUI.DebugArray("protos", fn)
            if next(protos) ~= nil then
                add(depth, "protos:")

                local count = 0
                for index, proto in protos do
                    count += 1
                    if count > max_items then
                        add(depth + 1, "-- protos truncated")
                        break
                    end

                    if type(proto) == "function" then
                        dumpfunction(
                            proto,
                            depth + 1,
                            ("proto_%s"):format(tostring(index))
                        )
                    else
                        add(
                            depth + 1,
                            ("[%s] = %s"):format(
                                tostring(index),
                                toolactions.ViewerUI.ValuePreview(proto)
                            )
                        )
                    end
                end
            end
        end

        add(depth, "end")
        lines[#lines + 1] = ""
    end

    dumpfunction(rootfn, 0, "root")

    return table.concat(lines, "\n")
end

toolactions.ViewerUI.SetSource = function(source)
    source = tostring(source or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    toolactions.ViewerUI.DisplayedText = source
    toolactions.ViewerUI.SelectionSource = source

    toolactions.ViewerUI.SelectionLoaded =
        #source <= toolactions.ViewerUI.SelectionLazyLimit

    toolactions.ViewerUI.RestoringSelectionText = true

    if toolactions.ViewerUI.SelectionLoaded then
        toolactions.ViewerUI.SelectionBox.Text = source
    else
        toolactions.ViewerUI.SelectionBox.Text = ""
    end

    toolactions.ViewerUI.RestoringSelectionText = false

    toolactions.ViewerUI.SelectionBox.CursorPosition = -1
    toolactions.ViewerUI.SelectionBox.SelectionStart = -1

    table.clear(toolactions.ViewerUI.SourceLines)
    toolactions.ViewerUI.MaxLineLength = 0
    toolactions.ViewerUI.LastFirstLine = -1

    for line in (source .. "\n"):gmatch("(.-)\n") do
        toolactions.ViewerUI.SourceLines[#toolactions.ViewerUI.SourceLines + 1] = line

        if #line > toolactions.ViewerUI.MaxLineLength then
            toolactions.ViewerUI.MaxLineLength = #line
        end
    end

    if #toolactions.ViewerUI.SourceLines == 0 then
        toolactions.ViewerUI.SourceLines[1] = ""
    end

    toolactions.ViewerUI.Scroll.CanvasPosition = Vector2.zero
    toolactions.ViewerUI.UpdateCanvas()
    toolactions.ViewerUI.RenderLines(true)
end

do
    for i = 1, toolactions.ViewerUI.LinePoolSize do
        local label = uifactory.Create("TextLabel", {
            Name = "Line" .. i,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.fromOffset(100, toolactions.ViewerUI.LineHeight),
            Font = Enum.Font.Code,
            TextSize = 15,
            TextColor3 = Color3.fromRGB(204, 204, 204),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextWrapped = false,
            RichText = true,
            Text = "",
            Visible = false,
            ZIndex = 504,
        }, toolactions.ViewerUI.Scroll)

        toolactions.ViewerUI.LinePool[i] = label
    end
end

toolactions.ViewerUI.Scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    toolactions.ViewerUI.RenderLines(false)
end)

toolactions.ViewerUI.Scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    toolactions.ViewerUI.UpdateCanvas()
    toolactions.ViewerUI.RenderLines(true)
end)

toolactions.ViewerUI.ResizeGrip = uifactory.Create("TextButton", {
    Name = "ResizeGrip",
    AutoButtonColor = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.new(1, -18, 1, -18),
    Size = UDim2.fromOffset(18, 18),
    Text = "◢",
    TextColor3 = Color3.fromRGB(120, 123, 130),
    TextSize = 12,
    Font = Enum.Font.Code,
    ZIndex = 505,
}, toolactions.ViewerUI.Window)

toolactions.ViewerUI.CopyButton.MouseButton1Click:Connect(function()
    local source = toolactions.ViewerUI.DisplayedText or ""
    adapter:Copy(source)
end)

toolactions.ViewerUI.SaveButton.MouseButton1Click:Connect(function()
    local source = toolactions.ViewerUI.DisplayedText or ""

    if type(adapter.writefile) ~= "function" then
        toolactions.ViewerUI.SaveButton.Text = "writefile unavailable"
        task.delay(1, function()
            if toolactions.ViewerUI.SaveButton and toolactions.ViewerUI.SaveButton.Parent then
                toolactions.ViewerUI.SaveButton.Text = "Save to File"
            end
        end)
        return
    end

    local filename =
        tostring(rawgame.PlaceId)
        .. "_Script_"
        .. tostring(os.time())
        .. ".txt"

    local ok = pcall(adapter.writefile, filename, source)

    toolactions.ViewerUI.SaveButton.Text =
        ok and "Saved" or "Save failed"

    task.delay(1, function()
        if toolactions.ViewerUI.SaveButton and toolactions.ViewerUI.SaveButton.Parent then
            toolactions.ViewerUI.SaveButton.Text = "Save to File"
        end
    end)
end)

toolactions.ViewerUI.DumpButton.MouseButton1Click:Connect(function()
    local targetscript = toolactions.ViewerUI.CurrentObject

    if not targetscript then
        return
    end

    toolactions.ViewerUI.DumpButton.Text = "Dumping..."

    task.spawn(function()
        local getgcfn = getgc or get_gc_objects
        local getfenvfn = getfenv
        local getupvaluesfn =
            (type(debug) == "table" and debug.getupvalues)
            or getupvalues
            or getupvals

        local getconstantsfn =
            (type(debug) == "table" and debug.getconstants)
            or getconstants
            or getconsts

        local getinfofn =
            (type(debug) == "table" and (debug.getinfo or debug.info))
            or getinfo

        if type(getgcfn) ~= "function"
            or type(getfenvfn) ~= "function"
            or type(getupvaluesfn) ~= "function"
            or type(getconstantsfn) ~= "function"
        then
            toolactions.ViewerUI.DumpButton.Text = "Unsupported"

            task.delay(1, function()
                if toolactions.ViewerUI.DumpButton and toolactions.ViewerUI.DumpButton.Parent then
                    toolactions.ViewerUI.DumpButton.Text = "Dump Functions"
                end
            end)
            return
        end

        local okpath, scriptpath = pcall(function()
            return targetscript:GetFullName()
        end)

        scriptpath = okpath and scriptpath or targetscript.Name

        local original =
            ("\n-- // Function Dumper made by King.Kevin\n"
            .. "-- // Script Path: %s\n\n--[[")
            :format(scriptpath)

        local dump = original
        local functioncount = 0
        local database = {}

        local function addtodump(str, indentation, newline)
            if newline == nil then
                newline = true
            end

            dump =
                dump
                .. string.rep("\t\t", math.max(0, indentation or 0))
                .. tostring(str)
                .. (newline and "\n" or "")
        end

        local function getfunctionname(fn)
            if type(getinfofn) ~= "function" then
                return "Unknown Name"
            end

            local ok, info = pcall(getinfofn, fn)

            if ok and type(info) == "table" then
                local name = info.name
                if type(name) == "string" and name ~= "" then
                    return name
                end
            end

            return "Unknown Name"
        end

        local dumptable
        local dumpfunction

        dumptable = function(input, indent, index)
            indent = math.max(0, indent or 0)

            addtodump(
                ("%s [%s] %s"):format(
                    tostring(index),
                    tostring(typeof(input)),
                    tostring(input)
                ),
                math.max(0, indent - 1)
            )

            local count = 0

            for key, value in input do
                count += 1

                if type(value) == "function" then
                    addtodump(
                        ("%d [function] = %s"):format(
                            count,
                            getfunctionname(value)
                        ),
                        indent
                    )
                elseif type(value) == "table" then
                    if not database[value] then
                        database[value] = true
                        addtodump(
                            ("%d [table]:"):format(count),
                            indent
                        )
                        dumptable(value, indent + 1, key)
                    else
                        addtodump(
                            ("%d [table] (Recursive table detected)")
                                :format(count),
                            indent
                        )
                    end
                else
                    addtodump(
                        ("%d [%s] = %s"):format(
                            count,
                            tostring(typeof(value)),
                            tostring(value)
                        ),
                        indent
                    )
                end

                if count % 200 == 0 then
                    task.wait()
                end
            end
        end

        dumpfunction = function(fn, indent)
            functioncount += 1

            addtodump(
                ("\nFunction Dump: %s"):format(
                    getfunctionname(fn)
                ),
                indent
            )

            addtodump(
                ("\nFunction Upvalues: %s"):format(
                    getfunctionname(fn)
                ),
                indent
            )

            local okupvalues, upvalues =
                pcall(getupvaluesfn, fn)

            if okupvalues and type(upvalues) == "table" then
                for index, upvalue in upvalues do
                    if type(upvalue) == "function" then
                        addtodump(
                            ("%d [function] = %s"):format(
                                index,
                                getfunctionname(upvalue)
                            ),
                            indent + 1
                        )
                    elseif type(upvalue) == "table" then
                        if not database[upvalue] then
                            database[upvalue] = true
                            addtodump(
                                ("%d [table]:"):format(index),
                                indent + 1
                            )
                            dumptable(
                                upvalue,
                                indent + 2,
                                index
                            )
                        else
                            addtodump(
                                ("%d [table] (Recursive table detected)")
                                    :format(index),
                                indent + 1
                            )
                        end
                    else
                        addtodump(
                            ("%d [%s] = %s"):format(
                                index,
                                tostring(typeof(upvalue)),
                                tostring(upvalue)
                            ),
                            indent + 1
                        )
                    end
                end
            end

            addtodump(
                ("\nFunction Constants: %s"):format(
                    getfunctionname(fn)
                ),
                indent
            )

            local okconstants, constants =
                pcall(getconstantsfn, fn)

            if okconstants and type(constants) == "table" then
                for index, constant in constants do
                    if type(constant) == "function" then
                        addtodump(
                            ("%d [function] = %s"):format(
                                index,
                                getfunctionname(constant)
                            ),
                            indent + 1
                        )
                    elseif type(constant) == "table" then
                        if not database[constant] then
                            database[constant] = true
                            addtodump(
                                ("%d [table]:"):format(index),
                                indent + 1
                            )
                            dumptable(
                                constant,
                                indent + 2,
                                index
                            )
                        else
                            addtodump(
                                ("%d [table] (Recursive table detected)")
                                    :format(index),
                                indent + 1
                            )
                        end
                    else
                        addtodump(
                            ("%d [%s] = %s"):format(
                                index,
                                tostring(typeof(constant)),
                                tostring(constant)
                            ),
                            indent + 1
                        )
                    end
                end
            end
        end

        local okgc, gcobjects = pcall(getgcfn)

        if okgc and type(gcobjects) == "table" then
            local scanned = 0

            for _, candidate in gcobjects do
                scanned += 1

                if typeof(candidate) == "function" then
                    local okenv, env = pcall(getfenvfn, candidate)

                    if okenv
                        and type(env) == "table"
                        and env.script == targetscript
                    then
                        pcall(dumpfunction, candidate, 0)
                        addtodump(
                            "\n" .. string.rep("=", 100),
                            0,
                            false
                        )
                    end
                end

                if scanned % 250 == 0 then
                    task.wait()
                end
            end
        end

        if toolactions.ViewerUI.CurrentObject ~= targetscript then
            return
        end

        if dump ~= original then
            local source =
                (toolactions.ViewerUI.DisplayedText or "")
                .. dump
                .. "]]"

            toolactions.ViewerUI.SetSource(source)
            toolactions.ViewerUI.DumpButton.Text =
                ("Dumped %d"):format(functioncount)
        else
            toolactions.ViewerUI.DumpButton.Text = "No Functions"
        end

        task.delay(1, function()
            if toolactions.ViewerUI.DumpButton and toolactions.ViewerUI.DumpButton.Parent then
                toolactions.ViewerUI.DumpButton.Text = "Dump Functions"
            end
        end)
    end)
end)

toolactions.ViewerUI.Close.MouseButton1Click:Connect(function()
    toolactions.ViewerUI.RequestId += 1
    toolactions.ViewerUI.CurrentObject = nil
    toolactions.ViewerUI.ShowingDump = false
    toolactions.ViewerUI.CopyButton.Text = "Copy to Clipboard"
    toolactions.ViewerUI.SaveButton.Text = "Save to File"
    toolactions.ViewerUI.DumpButton.Text = "Dump Functions"

    pcall(function()
        toolactions.ViewerUI.SelectionBox:ReleaseFocus()
    end)

    toolactions.ViewerUI.Overlay.Visible = false
end)

do
    local dragging = false
    local dragstart = nil
    local startposition = nil

    toolactions.ViewerUI.Top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragstart = input.Position
            startposition = toolactions.ViewerUI.Window.Position
        end
    end)

    uis.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - dragstart

            toolactions.ViewerUI.Window.Position = UDim2.new(
                startposition.X.Scale,
                startposition.X.Offset + d.X,
                startposition.Y.Scale,
                startposition.Y.Offset + d.Y
            )
        end
    end)

    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

do
    local resizing = false
    local startmouse = nil
    local startsize = nil

    toolactions.ViewerUI.ResizeGrip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = true
            startmouse = input.Position
            startsize = toolactions.ViewerUI.Window.AbsoluteSize
        end
    end)

    uis.InputChanged:Connect(function(input)
        if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - startmouse
            toolactions.ViewerUI.Window.Size = UDim2.fromOffset(
                math.clamp(startsize.X + d.X, 430, 1200),
                math.clamp(startsize.Y + d.Y, 300, 900)
            )
        end
    end)

    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = false
        end
    end)
end

toolactions.OpenScriptViewer = function(obj)
    if not obj then
        return
    end

    toolactions.ViewerUI.RequestId += 1
    local requestid = toolactions.ViewerUI.RequestId

    toolactions.ViewerUI.CurrentObject = obj
    toolactions.ViewerUI.CurrentSource = ""
    toolactions.ViewerUI.CurrentDump = ""
    toolactions.ViewerUI.ShowingDump = false
    toolactions.ViewerUI.DumpButton.Text = "Dump Functions"

    toolactions.ViewerUI.Title.Text =
        "Script Viewer  —  " .. obj:GetFullName()

    toolactions.ViewerUI.SetSource("-- Decompiling...")
    toolactions.ViewerUI.Overlay.Visible = true

    local window = toolactions.ViewerUI.Window
    local screen = rootgui.AbsoluteSize
    local pos = window.AbsolutePosition
    local size = window.AbsoluteSize

    if pos.X + 60 > screen.X
        or pos.Y + 40 > screen.Y
        or pos.X + size.X < 60
        or pos.Y + size.Y < 40
    then
        window.AnchorPoint = Vector2.new(0.5, 0.5)
        window.Position = UDim2.fromScale(0.5, 0.5)
    end

    task.spawn(function()

        pcall(function()
            runservice.RenderStepped:Wait()
        end)

        local src, err = adapter:Decompile(obj)

        if requestid ~= toolactions.ViewerUI.RequestId then
            return
        end

        if not toolactions.ViewerUI.Overlay.Parent then
            return
        end

        if not src then
            toolactions.ViewerUI.CurrentSource =
                "-- Explorer\n-- " .. tostring(err)
        else
            toolactions.ViewerUI.CurrentSource =
                src:gsub("\0", "\\0")
        end

        toolactions.ViewerUI.SetSource(
            toolactions.ViewerUI.CurrentSource
        )
    end)
end

toolactions.ViewScript = function()
    if selectednode and selectednode.obj and (
        selectednode.obj:IsA("LocalScript")
        or selectednode.obj:IsA("ModuleScript")
        or selectednode.obj:IsA("Script")
    ) then
        toolactions.OpenScriptViewer(selectednode.obj)
    else
        statuslabel.Text = "Select a Script / LocalScript / ModuleScript first"
    end
end

local row_h = 24
local tree_pool = 46
local nodesbyobject: {[Instance]: ExplorerNode} = setmetatable({}, {__mode = "k"}) :: any

local root: ExplorerNode = {
    obj = rawgame,
    parent = nil,
    depth = -1,
    expanded = true,
    loaded = false,
    children = {},
    pseudo = false,
    hasChildren = nil,
    sortDirty = false,
}

nodesbyobject[rawgame] = root

function treecontroller.GetOrCreateNode(obj: Instance, parentnode: ExplorerNode?): ExplorerNode
    local n = nodesbyobject[obj]
    if n then
        if parentnode then n.parent = parentnode end
        return n
    end

    n = {
        obj = obj,
        parent = parentnode,
        depth = parentnode and (parentnode.depth + 1) or 0,
        expanded = false,
        loaded = false,
        children = {},
        pseudo = false,

        hasChildren = nil,
        sortDirty = false,
    }
    nodesbyobject[obj] = n
    return n
end

local root_service_order = {
    "Workspace",
    "Players",
    "Lighting",
    "ReplicatedFirst",
    "ReplicatedStorage",
    "Packages",
    "StarterGui",
    "StarterPack",
    "StarterPlayer",
    "SoundService",
    "TextChatService",
    "Chat",
    "LocalizationService",
    "TestService",
    "Teams",
    "InsertService",
    "AssetService",
    "CollectionService",
    "TweenService",
    "RunService",
    "HttpService",
    "MarketplaceService",
    "TeleportService",
    "UserInputService",
    "ContextActionService",
    "GuiService",
    "CoreGui",
    "CorePackages",
    "ScriptContext",
    "Stats",
    "MaterialService",
    "PhysicsService",
    "PathfindingService",
    "ProximityPromptService",
    "BadgeService",
    "GamePassService",
    "GroupService",
    "MemStorageService",
    "ChangeHistoryService",
    "Selection",
    "StudioService",
    "PluginGuiService",
}

local root_service_index = {}
for i, name in root_service_order do
    root_service_index[name] = i
end

function treecontroller.GetRootOrderName(obj: Instance?): string?
    if obj == nil or typeof(obj) ~= "Instance" then
        return nil
    end

    local parentobj = obj.Parent
    if parentobj ~= rawgame then return nil end
    local classname = obj.ClassName
    local name = obj.Name

    if root_service_index[classname] then return classname end
    if root_service_index[name] then return name end

    local ok, fullname = pcall(function() return obj:GetFullName() end)
    if ok and fullname:find("^game%.") then
        local seg = fullname:match("^game%.([^%.%[]+)")
        if seg and root_service_index[seg] then
            return seg
        end
    end
    return nil
end

function treecontroller.CompareNodes(a: ExplorerNode, b: ExplorerNode): boolean
    local ao, bo = a and a.obj, b and b.obj

    if not ao or not bo then
        return ao ~= nil
    end

    local ac, bc = ao.ClassName, bo.ClassName

    local ar = metadata:GetExplorerOrder(ac)
    local br = metadata:GetExplorerOrder(bc)

    if ar ~= nil or br ~= nil then
        local ai = ar or 9999
        local bi = br or 9999

        if ai ~= bi then
            return ai < bi
        end
    end

    local an = tostring(ao.Name):lower()
    local bn = tostring(bo.Name):lower()

    if an ~= bn then
        return an < bn
    end

    return ac < bc
end

function treecontroller.LoadChildren(node: ExplorerNode)
    if node.loaded then
        if node.sortDirty then
            table.sort(node.children, treecontroller.CompareNodes)
            node.sortDirty = false
        end
        return
    end

    node.loaded = true
    table.clear(node.children)

    local ok, children = pcall(function()
        return node.obj:GetChildren()
    end)

    if not ok then
        node.hasChildren = false
        return
    end

    node.hasChildren = #children > 0

    for _, obj in children do
        node.children[#node.children + 1] = treecontroller.GetOrCreateNode(obj, node)
    end

    if #node.children > 1 then
        table.sort(node.children, treecontroller.CompareNodes)
    end

    node.sortDirty = false
end

treecontroller.LoadChildren(root)

local nilroot: ExplorerNode? = nil
if adapter.getnilinstances then
    nilroot = {
        obj = nil,
        name = "[Nil Instances]",
        className = "Folder",
        parent = nil,
        depth = 0,
        expanded = false,
        loaded = false,
        children = {},
        pseudo = true,
        hasChildren = nil,
        sortDirty = false,
    }
end

function treecontroller.LoadNilChildren()
    if not nilroot or nilroot.loaded then return end
    nilroot.loaded = true
    table.clear(nilroot.children)

    local ok, list = pcall(adapter.getnilinstances)
    if not ok or type(list) ~= "table" then return end

    local seen = {}
    for _, obj in list do
        if typeof(obj) == "Instance" and obj ~= rawgame and obj.Parent == nil and not seen[obj] then
            seen[obj] = true
            local n = treecontroller.GetOrCreateNode(obj, nilroot)
            n.depth = 1
            nilroot.children[#nilroot.children + 1] = n
        end
    end
    nilroot.hasChildren = #nilroot.children > 0
    if #nilroot.children > 1 then
        table.sort(nilroot.children, treecontroller.CompareNodes)
    end
    nilroot.sortDirty = false
end

local visiblenodes: {ExplorerNode} = {}
local searchmode = false
local searchgeneration = 0

function treecontroller.BuildVisible()
    table.clear(visiblenodes)

    local stack = {}

    for i = #root.children, 1, -1 do
        local child = root.children[i]
        child.depth = 0
        stack[#stack + 1] = child
    end

    while #stack > 0 do
        local node = table.remove(stack)
        visiblenodes[#visiblenodes + 1] = node

        if node.expanded and node.loaded then
            if node.sortDirty then
                table.sort(node.children, treecontroller.CompareNodes)
                node.sortDirty = false
            end

            local nextdepth = (node.depth or 0) + 1
            for i = #node.children, 1, -1 do
                local child = node.children[i]
                child.depth = nextdepth
                stack[#stack + 1] = child
            end
        end
    end

    if nilroot then
        visiblenodes[#visiblenodes + 1] = nilroot

        if nilroot.expanded and nilroot.loaded then
            if nilroot.sortDirty then
                table.sort(nilroot.children, treecontroller.CompareNodes)
                nilroot.sortDirty = false
            end

            for _, child in nilroot.children do
                child.depth = 1
                visiblenodes[#visiblenodes + 1] = child
            end
        end
    end
end

function treecontroller.GetPath(obj: Instance?): string
    if not obj then return "[Nil Instances]" end

    local parts = {}
    local cur = obj

    while cur and cur ~= rawgame do
        local name = cur.Name
        local classname = cur.ClassName
        local parentobj = cur.Parent

        local segment
        if parentobj == rawgame then
            local cls = metadata.Classes[classname]
            if cls and cls.Tags and cls.Tags.Service then
                segment = (':GetService("%s")'):format(classname)
            else
                segment = ('[%q]'):format(name)
            end
        elseif name:match("^[%a_][%w_]*$") then
            segment = "." .. name
        else
            segment = ('[%q]'):format(name)
        end

        table.insert(parts, 1, segment)
        cur = parentobj
    end

    if not cur then
        return ('getnilinstances() -- %s <%s>'):format(obj.Name, obj.ClassName)
    end

    return "game" .. table.concat(parts)
end

local treerows = {}
selectednode = nil

function treecontroller.CreateRow(i: number)
    local row = uifactory.Create("TextButton", {
        Name = "Row" .. i,
        Size = UDim2.new(1, -4, 0, row_h),
        BackgroundColor3 = theme.Panel,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Visible = false,
    }, treescroll)

    local expand = uifactory.Create("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = theme.Dim,
        TextSize = 8,
        Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
    }, row)
    expand.Name = "Expand"
    expand.Size = UDim2.fromOffset(16, row_h)
    expand.Position = UDim2.fromOffset(2, 0)

    local icon = uifactory.Create("ImageLabel", {
        Name = "Icon",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.fromOffset(22, math.floor((row_h - 16) / 2)),
        ScaleType = Enum.ScaleType.Crop,
        Visible = false,
    }, row)

    local badge = uifactory.Create("Frame", {
        Name = "Badge",
        BackgroundColor3 = Color3.fromRGB(78, 106, 132),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(16, 12),
        Position = UDim2.fromOffset(22, math.floor((row_h - 12) / 2)),
        Visible = false,
    }, row)
    uifactory.Round(badge, 2)

    local badgetext = uifactory.Text(badge, "", 7, Enum.TextXAlignment.Center)
    badgetext.Name = "BadgeText"
    badgetext.Size = UDim2.new(1, 0, 1, 0)
    badgetext.TextColor3 = Color3.fromRGB(240, 240, 240)
    badgetext.Font = Enum.Font.Code
    badgetext.TextYAlignment = Enum.TextYAlignment.Center

    local txt = uifactory.Text(row, "", 17)
    txt.Name = "Label"
    txt.TextTruncate = Enum.TextTruncate.AtEnd

    row.MouseEnter:Connect(function()
        local node = row:GetAttribute("NodeIndex") and visiblenodes[row:GetAttribute("NodeIndex")]
        if node and not toolactions.Selection.Set[node] then
            row.BackgroundTransparency = 0
            row.BackgroundColor3 = theme.Hover
        end
    end)

    row.MouseLeave:Connect(function()
        local node = row:GetAttribute("NodeIndex") and visiblenodes[row:GetAttribute("NodeIndex")]
        if not toolactions.Selection.Set[node] then
            row.BackgroundTransparency = 1
        end
    end)

    treerows[i] = {
        Root = row,
        Expand = expand,
        Icon = icon,
        Badge = badge,
        BadgeText = badgetext,
        Label = txt
    }
end

for i = 1, tree_pool do treecontroller.CreateRow(i) end

local proprows = {}
local propertylist: {PropertyEntry} = {}
local propertychangedconn = nil
local prop_h = 25
local prop_pool = 32

function valuecodec.ToString(v)
    local t = typeof(v)
    if t == "string" then return v end
    if t == "Instance" then
        return v and v.Name or "nil"
    end
    if t == "EnumItem" then
        return v.Name
    end
    if t == "Color3" then
        return ("[%d, %d, %d]"):format(
            math.floor(v.R * 255 + 0.5),
            math.floor(v.G * 255 + 0.5),
            math.floor(v.B * 255 + 0.5)
        )
    end
    return tostring(v)
end

function valuecodec.ReadProperty(obj: Instance, name: string): (any, boolean)
    local ok, v = pcall(function() return obj[name] end)
    if ok then return v, true end
    return "<unavailable>", false
end

toolactions.RuntimePropertyEntry = function(obj, meta)
    local value, readable = valuecodec.ReadProperty(obj, meta.Name)

    if not readable then
        return nil
    end

    return {
        Name = meta.Name,
        Category = meta.Category or "Other",
        ValueType = meta.ValueType or typeof(value),
        ValueCategory = meta.ValueCategory,
        Tags = meta.Tags,
        ReadSecurity = meta.ReadSecurity,
        WriteSecurity = meta.WriteSecurity,
        DeclaredClass = meta.DeclaredClass,
        ReadOnly = not metadata:IsPropertyWritable(meta),
    }
end

function valuecodec.SplitNumbers(text)
    local out = {}
    for n in tostring(text):gmatch("[-+]?%d*%.?%d+") do
        out[#out + 1] = tonumber(n)
    end
    return out
end

function valuecodec.Parse(text, typename, oldvalue)
    text = runtimeutil.Trim(text)

    if typename == "string" or typename == "Content" or typename == "ContentId" then
        return text, true
    elseif typename == "bool" then
        local l = text:lower()
        if l == "true" or l == "1" then return true, true end
        if l == "false" or l == "0" then return false, true end
        return nil, false
    elseif typename == "number" or typename == "int" or typename == "int64" or typename == "float" or typename == "double" then
        local n = tonumber(text)
        return n, n ~= nil
    elseif typename == "Vector2" then
        local n = valuecodec.SplitNumbers(text)
        if #n >= 2 then return Vector2.new(n[1], n[2]), true end
    elseif typename == "Vector3" then
        local n = valuecodec.SplitNumbers(text)
        if #n >= 3 then return Vector3.new(n[1], n[2], n[3]), true end
    elseif typename == "UDim" then
        local n = valuecodec.SplitNumbers(text)
        if #n >= 2 then return UDim.new(n[1], n[2]), true end
    elseif typename == "UDim2" then
        local n = valuecodec.SplitNumbers(text)
        if #n >= 4 then return UDim2.new(n[1], n[2], n[3], n[4]), true end
    elseif typename == "Color3" then
        local n = valuecodec.SplitNumbers(text)
        if #n >= 3 then
            if math.max(n[1], n[2], n[3]) > 1 then
                return Color3.fromRGB(runtimeutil.Clamp(n[1],0,255), runtimeutil.Clamp(n[2],0,255), runtimeutil.Clamp(n[3],0,255)), true
            end
            return Color3.new(n[1], n[2], n[3]), true
        end
    elseif typename == "CFrame" then
        local n = valuecodec.SplitNumbers(text)
        if #n >= 3 then return CFrame.new(n[1], n[2], n[3]), true end
    elseif typename == "BrickColor" then
        local ok, v = pcall(BrickColor.new, text)
        if ok then return v, true end
    elseif typeof(oldvalue) == "EnumItem" then
        local enumtype = tostring(oldvalue.EnumType):gsub("^Enum%.", "")
        local itemname = text:gsub("^Enum%." .. enumtype .. "%.", "")
        local enumtable = Enum[enumtype]

        if enumtable then
            local ok, v = pcall(function()
                return enumtable[itemname]
            end)

            if ok and v ~= nil then
                return v, true
            end
        end
    end

    return oldvalue, false
end

function valuecodec.WriteProperty(prop, newvalue, refresh)
    if not selectednode or not selectednode.obj or not prop or prop.ReadOnly then
        return false
    end

    local obj = selectednode.obj
    local ok

    if prop.Special == "Attribute" then
        ok = pcall(function()
            obj:SetAttribute(prop.AttrName, newvalue)
        end)
    else
        ok = pcall(function()
            obj[prop.Name] = newvalue
        end)
    end

    if ok and refresh ~= false then
        if toolactions.RebuildProperties then
            toolactions.RebuildProperties()
        end
        if toolactions.RenderProperties then
            toolactions.RenderProperties()
        end
    end

    return ok
end

function propertycontroller.CloseDropdown()
    if propertydropdownstate.Frame then
        propertydropdownstate.Frame.Visible = false
    end

    propertydropdownstate.ActiveRow = nil
end

toolactions.PropertyExpanded = toolactions.PropertyExpanded or {}

toolactions.PropertyKey = function(prop)
    if not prop then
        return ""
    end

    if prop.Special == "Attribute" then
        return "Attribute|" .. tostring(prop.AttrName or prop.Name)
    end

    local classname =
        selectednode
        and selectednode.obj
        and selectednode.obj.ClassName
        or ""

    return classname .. "|" .. tostring(prop.Name)
end

toolactions.ReadBasePropertyValue = function(prop)
    if not selectednode or not selectednode.obj or not prop then
        return nil, false
    end

    if prop.Special == "Attribute" then
        return selectednode.obj:GetAttribute(prop.AttrName), true
    end

    if prop.Special == "Tag" then
        return prop.TagName, true
    end

    return valuecodec.ReadProperty(selectednode.obj, prop.Name)
end

toolactions.GetComponentSpecs = function(value)
    local t = typeof(value)
    local out = {}

    if t == "Vector2" then
        out = {
            {Name = "X", Key = "X", Value = value.X},
            {Name = "Y", Key = "Y", Value = value.Y},
        }
    elseif t == "Vector3" then
        out = {
            {Name = "X", Key = "X", Value = value.X},
            {Name = "Y", Key = "Y", Value = value.Y},
            {Name = "Z", Key = "Z", Value = value.Z},
        }
    elseif t == "UDim" then
        out = {
            {Name = "Scale", Key = "Scale", Value = value.Scale},
            {Name = "Offset", Key = "Offset", Value = value.Offset},
        }
    elseif t == "UDim2" then
        out = {
            {Name = "X Scale", Key = "X.Scale", Value = value.X.Scale},
            {Name = "X Offset", Key = "X.Offset", Value = value.X.Offset},
            {Name = "Y Scale", Key = "Y.Scale", Value = value.Y.Scale},
            {Name = "Y Offset", Key = "Y.Offset", Value = value.Y.Offset},
        }
    elseif t == "CFrame" then
        local rx, ry, rz = value:ToOrientation()
        out = {
            {Name = "Position X", Key = "Position.X", Value = value.Position.X},
            {Name = "Position Y", Key = "Position.Y", Value = value.Position.Y},
            {Name = "Position Z", Key = "Position.Z", Value = value.Position.Z},
            {Name = "Orientation X", Key = "Orientation.X", Value = math.deg(rx)},
            {Name = "Orientation Y", Key = "Orientation.Y", Value = math.deg(ry)},
            {Name = "Orientation Z", Key = "Orientation.Z", Value = math.deg(rz)},
        }
    elseif t == "Rect" then
        out = {
            {Name = "Min X", Key = "Min.X", Value = value.Min.X},
            {Name = "Min Y", Key = "Min.Y", Value = value.Min.Y},
            {Name = "Max X", Key = "Max.X", Value = value.Max.X},
            {Name = "Max Y", Key = "Max.Y", Value = value.Max.Y},
        }
    elseif t == "NumberRange" then
        out = {
            {Name = "Min", Key = "Min", Value = value.Min},
            {Name = "Max", Key = "Max", Value = value.Max},
        }
    elseif t == "PhysicalProperties" then
        out = {
            {Name = "Density", Key = "Density", Value = value.Density},
            {Name = "Friction", Key = "Friction", Value = value.Friction},
            {Name = "Elasticity", Key = "Elasticity", Value = value.Elasticity},
            {Name = "Friction Weight", Key = "FrictionWeight", Value = value.FrictionWeight},
            {Name = "Elasticity Weight", Key = "ElasticityWeight", Value = value.ElasticityWeight},
        }
    elseif t == "Axes" then
        out = {
            {Name = "X", Key = "Axes.X", Value = value.X},
            {Name = "Y", Key = "Axes.Y", Value = value.Y},
            {Name = "Z", Key = "Axes.Z", Value = value.Z},
        }
    elseif t == "Faces" then
        out = {
            {Name = "Top", Key = "Faces.Top", Value = value.Top},
            {Name = "Bottom", Key = "Faces.Bottom", Value = value.Bottom},
            {Name = "Left", Key = "Faces.Left", Value = value.Left},
            {Name = "Right", Key = "Faces.Right", Value = value.Right},
            {Name = "Front", Key = "Faces.Front", Value = value.Front},
            {Name = "Back", Key = "Faces.Back", Value = value.Back},
        }
    elseif t == "Font" then
        out = {
            {Name = "Family", Key = "Font.Family", Value = value.Family},
            {Name = "Weight", Key = "Font.Weight", Value = value.Weight},
            {Name = "Style", Key = "Font.Style", Value = value.Style},
        }
    elseif t == "TweenInfo" then
        out = {
            {Name = "Time", Key = "Tween.Time", Value = value.Time},
            {Name = "Easing Style", Key = "Tween.EasingStyle", Value = value.EasingStyle},
            {Name = "Easing Direction", Key = "Tween.EasingDirection", Value = value.EasingDirection},
            {Name = "Repeat Count", Key = "Tween.RepeatCount", Value = value.RepeatCount},
            {Name = "Reverses", Key = "Tween.Reverses", Value = value.Reverses},
            {Name = "Delay Time", Key = "Tween.DelayTime", Value = value.DelayTime},
        }
    elseif t == "Ray" then
        out = {
            {Name = "Origin X", Key = "Ray.Origin.X", Value = value.Origin.X},
            {Name = "Origin Y", Key = "Ray.Origin.Y", Value = value.Origin.Y},
            {Name = "Origin Z", Key = "Ray.Origin.Z", Value = value.Origin.Z},
            {Name = "Direction X", Key = "Ray.Direction.X", Value = value.Direction.X},
            {Name = "Direction Y", Key = "Ray.Direction.Y", Value = value.Direction.Y},
            {Name = "Direction Z", Key = "Ray.Direction.Z", Value = value.Direction.Z},
        }
    elseif t == "NumberSequence" then
        for i, kp in value.Keypoints do
            out[#out + 1] = {Name = "Key " .. i .. " Time", Key = "NS:" .. i .. ":Time", Value = kp.Time}
            out[#out + 1] = {Name = "Key " .. i .. " Value", Key = "NS:" .. i .. ":Value", Value = kp.Value}
            out[#out + 1] = {Name = "Key " .. i .. " Envelope", Key = "NS:" .. i .. ":Envelope", Value = kp.Envelope}
        end
    elseif t == "ColorSequence" then
        for i, kp in value.Keypoints do
            out[#out + 1] = {Name = "Key " .. i .. " Time", Key = "CS:" .. i .. ":Time", Value = kp.Time}
            out[#out + 1] = {Name = "Key " .. i .. " Color", Key = "CS:" .. i .. ":Color", Value = kp.Value}
        end
    end

    return out
end

toolactions.IsExpandableValue = function(value)
    local t = typeof(value)

    return
        t == "Vector2"
        or t == "Vector3"
        or t == "UDim"
        or t == "UDim2"
        or t == "CFrame"
        or t == "Rect"
        or t == "NumberRange"
        or t == "PhysicalProperties"
        or t == "Axes"
        or t == "Faces"
        or t == "Font"
        or t == "TweenInfo"
        or t == "Ray"
        or t == "NumberSequence"
        or t == "ColorSequence"
end

toolactions.GetComponentValue = function(parentvalue, key)
    local specs = toolactions.GetComponentSpecs(parentvalue)

    for _, spec in specs do
        if spec.Key == key then
            return spec.Value, true
        end
    end

    return nil, false
end

toolactions.ReadEntryValue = function(prop)
    if not prop then
        return nil, false
    end

    if prop.Special == "Component" then
        local parentvalue, readable =
            toolactions.ReadBasePropertyValue(prop.ParentProp)

        if not readable then
            return nil, false
        end

        return toolactions.GetComponentValue(
            parentvalue,
            prop.ComponentKey
        )
    end

    return toolactions.ReadBasePropertyValue(prop)
end

toolactions.SetPropertyComponentValue = function(prop, newvalue, refresh)
    if not prop or prop.Special ~= "Component" or not prop.ParentProp then
        return false
    end

    local oldvalue, readable =
        toolactions.ReadBasePropertyValue(prop.ParentProp)

    if not readable then
        return false
    end

    local t = typeof(oldvalue)
    local key = prop.ComponentKey
    local result

    local ok = pcall(function()
        if t == "Vector2" then
            result = Vector2.new(
                key == "X" and newvalue or oldvalue.X,
                key == "Y" and newvalue or oldvalue.Y
            )
        elseif t == "Vector3" then
            result = Vector3.new(
                key == "X" and newvalue or oldvalue.X,
                key == "Y" and newvalue or oldvalue.Y,
                key == "Z" and newvalue or oldvalue.Z
            )
        elseif t == "UDim" then
            result = UDim.new(
                key == "Scale" and newvalue or oldvalue.Scale,
                key == "Offset" and newvalue or oldvalue.Offset
            )
        elseif t == "UDim2" then
            result = UDim2.new(
                key == "X.Scale" and newvalue or oldvalue.X.Scale,
                key == "X.Offset" and newvalue or oldvalue.X.Offset,
                key == "Y.Scale" and newvalue or oldvalue.Y.Scale,
                key == "Y.Offset" and newvalue or oldvalue.Y.Offset
            )
        elseif t == "CFrame" then
            local pos = oldvalue.Position
            local rx, ry, rz = oldvalue:ToOrientation()

            if key == "Position.X" then pos = Vector3.new(newvalue, pos.Y, pos.Z) end
            if key == "Position.Y" then pos = Vector3.new(pos.X, newvalue, pos.Z) end
            if key == "Position.Z" then pos = Vector3.new(pos.X, pos.Y, newvalue) end
            if key == "Orientation.X" then rx = math.rad(newvalue) end
            if key == "Orientation.Y" then ry = math.rad(newvalue) end
            if key == "Orientation.Z" then rz = math.rad(newvalue) end

            result = CFrame.new(pos) * CFrame.Angles(rx, ry, rz)
        elseif t == "Rect" then
            result = Rect.new(
                key == "Min.X" and newvalue or oldvalue.Min.X,
                key == "Min.Y" and newvalue or oldvalue.Min.Y,
                key == "Max.X" and newvalue or oldvalue.Max.X,
                key == "Max.Y" and newvalue or oldvalue.Max.Y
            )
        elseif t == "NumberRange" then
            result = NumberRange.new(
                key == "Min" and newvalue or oldvalue.Min,
                key == "Max" and newvalue or oldvalue.Max
            )
        elseif t == "PhysicalProperties" then
            result = PhysicalProperties.new(
                key == "Density" and newvalue or oldvalue.Density,
                key == "Friction" and newvalue or oldvalue.Friction,
                key == "Elasticity" and newvalue or oldvalue.Elasticity,
                key == "FrictionWeight" and newvalue or oldvalue.FrictionWeight,
                key == "ElasticityWeight" and newvalue or oldvalue.ElasticityWeight
            )
        elseif t == "Axes" then
            local axes = {}
            local x = key == "Axes.X" and newvalue or oldvalue.X
            local y = key == "Axes.Y" and newvalue or oldvalue.Y
            local z = key == "Axes.Z" and newvalue or oldvalue.Z

            if x then axes[#axes + 1] = Enum.Axis.X end
            if y then axes[#axes + 1] = Enum.Axis.Y end
            if z then axes[#axes + 1] = Enum.Axis.Z end

            result = Axes.new(unpack(axes))
        elseif t == "Faces" then
            local faces = {}
            local values = {
                Top = key == "Faces.Top" and newvalue or oldvalue.Top,
                Bottom = key == "Faces.Bottom" and newvalue or oldvalue.Bottom,
                Left = key == "Faces.Left" and newvalue or oldvalue.Left,
                Right = key == "Faces.Right" and newvalue or oldvalue.Right,
                Front = key == "Faces.Front" and newvalue or oldvalue.Front,
                Back = key == "Faces.Back" and newvalue or oldvalue.Back,
            }

            if values.Top then faces[#faces + 1] = Enum.NormalId.Top end
            if values.Bottom then faces[#faces + 1] = Enum.NormalId.Bottom end
            if values.Left then faces[#faces + 1] = Enum.NormalId.Left end
            if values.Right then faces[#faces + 1] = Enum.NormalId.Right end
            if values.Front then faces[#faces + 1] = Enum.NormalId.Front end
            if values.Back then faces[#faces + 1] = Enum.NormalId.Back end

            result = Faces.new(unpack(faces))
        elseif t == "Font" then
            result = Font.new(
                key == "Font.Family" and newvalue or oldvalue.Family,
                key == "Font.Weight" and newvalue or oldvalue.Weight,
                key == "Font.Style" and newvalue or oldvalue.Style
            )
        elseif t == "TweenInfo" then
            result = TweenInfo.new(
                key == "Tween.Time" and newvalue or oldvalue.Time,
                key == "Tween.EasingStyle" and newvalue or oldvalue.EasingStyle,
                key == "Tween.EasingDirection" and newvalue or oldvalue.EasingDirection,
                key == "Tween.RepeatCount" and newvalue or oldvalue.RepeatCount,
                key == "Tween.Reverses" and newvalue or oldvalue.Reverses,
                key == "Tween.DelayTime" and newvalue or oldvalue.DelayTime
            )
        elseif t == "Ray" then
            local origin = oldvalue.Origin
            local direction = oldvalue.Direction

            if key == "Ray.Origin.X" then origin = Vector3.new(newvalue, origin.Y, origin.Z) end
            if key == "Ray.Origin.Y" then origin = Vector3.new(origin.X, newvalue, origin.Z) end
            if key == "Ray.Origin.Z" then origin = Vector3.new(origin.X, origin.Y, newvalue) end
            if key == "Ray.Direction.X" then direction = Vector3.new(newvalue, direction.Y, direction.Z) end
            if key == "Ray.Direction.Y" then direction = Vector3.new(direction.X, newvalue, direction.Z) end
            if key == "Ray.Direction.Z" then direction = Vector3.new(direction.X, direction.Y, newvalue) end

            result = Ray.new(origin, direction)
        elseif t == "NumberSequence" then
            local parts = {}
            for token in key:gmatch("[^:]+") do parts[#parts + 1] = token end
            local targetindex = tonumber(parts[2])
            local field = parts[3]
            local points = {}

            for i, kp in oldvalue.Keypoints do
                points[i] = NumberSequenceKeypoint.new(
                    i == targetindex and field == "Time" and newvalue or kp.Time,
                    i == targetindex and field == "Value" and newvalue or kp.Value,
                    i == targetindex and field == "Envelope" and newvalue or kp.Envelope
                )
            end

            result = NumberSequence.new(points)
        elseif t == "ColorSequence" then
            local parts = {}
            for token in key:gmatch("[^:]+") do parts[#parts + 1] = token end
            local targetindex = tonumber(parts[2])
            local field = parts[3]
            local points = {}

            for i, kp in oldvalue.Keypoints do
                points[i] = ColorSequenceKeypoint.new(
                    i == targetindex and field == "Time" and newvalue or kp.Time,
                    i == targetindex and field == "Color" and newvalue or kp.Value
                )
            end

            result = ColorSequence.new(points)
        end
    end)

    if not ok or result == nil then
        return false
    end

    return valuecodec.WriteProperty(prop.ParentProp, result, refresh)
end

toolactions.WriteEntryValue = function(prop, newvalue, refresh)
    if prop and prop.Special == "Component" then
        return toolactions.SetPropertyComponentValue(prop, newvalue, refresh)
    end

    return valuecodec.WriteProperty(prop, newvalue, refresh)
end

function propertycontroller.GetDropdownItems(prop, currentvalue)
    local items = {}
    local valuetype = typeof(currentvalue)

    if valuetype == "EnumItem" then
        local runtimeitems = {}
        local enumtype = currentvalue.EnumType

        local ok, result = pcall(function()
            return enumtype:GetEnumItems()
        end)

        if ok and type(result) == "table" then
            runtimeitems = result
        end

        if #runtimeitems > 0 then
            table.sort(runtimeitems, function(a, b)
                return a.Name:lower() < b.Name:lower()
            end)

            for _, enumitem in runtimeitems do
                items[#items + 1] = {
                    Text = enumitem.Name,
                    Detail = "",
                    Selected = enumitem == currentvalue,
                    Value = enumitem,
                }
            end
        else
            local enumtypename = tostring(enumtype):gsub("^Enum%.", "")
            local metadataitems = metadata:GetEnumItems(enumtypename)

            for _, item in metadataitems do
                local enumvalue

                pcall(function()
                    enumvalue = enumtype[item.Name]
                end)

                if enumvalue then
                    items[#items + 1] = {
                        Text = item.Name,
                        Detail = "",
                        Selected = tostring(currentvalue) == item.FullName,
                        Value = enumvalue,
                    }
                end
            end
        end
    elseif valuetype == "BrickColor" then
        local seen = {}

        for paletteindex = 0, 127 do
            local ok, bc = pcall(BrickColor.palette, paletteindex)

            if ok and typeof(bc) == "BrickColor" and not seen[bc.Number] then
                seen[bc.Number] = true

                items[#items + 1] = {
                    Text = tostring(bc),
                    Detail = "",
                    Selected = currentvalue.Number == bc.Number,
                    Color = bc.Color,
                    Value = bc,
                }
            end
        end

        table.sort(items, function(a, b)
            return a.Text:lower() < b.Text:lower()
        end)
    end

    return items
end

function propertycontroller.OpenDropdown(row, prop, currentvalue)
    if not row or not prop or prop.ReadOnly then
        return
    end

    local items = propertycontroller.GetDropdownItems(prop, currentvalue)
    if #items == 0 then
        return
    end

    if toolactions.CloseColorPicker then
        toolactions.CloseColorPicker()
    end

    local frame = propertydropdownstate.Frame
    local scroll = propertydropdownstate.Scroll

    for _, child in scroll:GetChildren() do
        if not child:IsA("UIListLayout") then
            child:Destroy()
        end
    end

    local list = scroll:FindFirstChild("ListLayout")
    if not list then
        list = uifactory.Create("UIListLayout", {
            Name = "ListLayout",
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 0),
        }, scroll)
    end

    local panewidth = propertiespane.AbsoluteSize.X
    local width = math.min(
        math.max(220, propertycontroller.GetViewportWidth() - prop_name_w - 8),
        math.max(80, panewidth - 8)
    )

    local itemheight = 24
    local height = math.min(240, #items * itemheight + 2)
    local localx =
        row.AbsolutePosition.X
        - propertiespane.AbsolutePosition.X
        + prop_name_w
        + 4
    localx = math.max(4, math.min(localx, panewidth - width - 4))

    local localy =
        row.AbsolutePosition.Y
        - propertiespane.AbsolutePosition.Y
        + row.AbsoluteSize.Y
        - 1

    if localy + height > propertiespane.AbsoluteSize.Y - 4 then
        localy =
            math.max(
                32,
                row.AbsolutePosition.Y
                - propertiespane.AbsolutePosition.Y
                - height
                + 1
            )
    end

    frame.Position = UDim2.fromOffset(localx, localy)
    frame.Size = UDim2.fromOffset(width, height)
    frame.Visible = true

    for i = 1, #items do
        local item = items[i]

        local button = uifactory.Create("TextButton", {
            Size = UDim2.new(1, 0, 0, itemheight),
            BackgroundColor3 =
                item.Selected
                and theme.Hover
                or Color3.fromRGB(31, 31, 31),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            ZIndex = 52,
        }, scroll)

        button.MouseEnter:Connect(function()
            button.BackgroundColor3 = theme.Hover
        end)

        button.MouseLeave:Connect(function()
            button.BackgroundColor3 =
                item.Selected
                and theme.Hover
                or Color3.fromRGB(31, 31, 31)
        end)

        if item.Color then
            local swatch = uifactory.Create("Frame", {
                Position = UDim2.fromOffset(6, 4),
                Size = UDim2.fromOffset(14, 14),
                BackgroundColor3 = item.Color,
                BorderSizePixel = 0,
                ZIndex = 53,
            }, button)

            uifactory.Stroke(swatch, Color3.fromRGB(120, 120, 120))
        end

        local label = uifactory.Text(button, item.Text, 15)
        label.Position = UDim2.fromOffset(item.Color and 28 or 8, 0)
        label.Size = UDim2.new(1, -16, 1, 0)
        label.ZIndex = 53
        label.TextColor3 = theme.Text
        label.TextTruncate = Enum.TextTruncate.AtEnd

        button.MouseButton1Click:Connect(function()
            toolactions.WriteEntryValue(prop, item.Value)
            propertycontroller.CloseDropdown()
        end)
    end

    scroll.CanvasSize = UDim2.fromOffset(0, #items * itemheight)
    propertydropdownstate.ActiveRow = row
end

toolactions.ColorPicker = toolactions.ColorPicker or {}
toolactions.ColorPicker.State = {
    Prop = nil,
    Row = nil,
    H = 0,
    S = 0,
    V = 1,
    DragSV = false,
    DragHue = false,
}

toolactions.ColorPicker.Frame = uifactory.Create("Frame", {
    Name = "ColorPicker",
    Visible = false,
    BackgroundColor3 = Color3.fromRGB(31, 31, 31),
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(300, 298),
    ZIndex = 70,
}, rootgui)
uifactory.Round(toolactions.ColorPicker.Frame, 6)
uifactory.Stroke(toolactions.ColorPicker.Frame, theme.Border)

toolactions.ColorPicker.Title = uifactory.Text(
    toolactions.ColorPicker.Frame,
    "Color3",
    15
)
toolactions.ColorPicker.Title.Position = UDim2.fromOffset(12, 0)
toolactions.ColorPicker.Title.Size = UDim2.new(1, -44, 0, 30)
toolactions.ColorPicker.Title.ZIndex = 71

uifactory.Create("Frame", {
    Position = UDim2.fromOffset(0, 30),
    Size = UDim2.new(1, 0, 0, 1),
    BackgroundColor3 = theme.BorderSoft,
    BorderSizePixel = 0,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)

toolactions.ColorPicker.Close = uifactory.Create("TextButton", {
    Position = UDim2.new(1, -30, 0, 2),
    Size = UDim2.fromOffset(26, 26),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "×",
    TextColor3 = theme.Dim,
    TextSize = 18,
    Font = Enum.Font.SourceSans,
    ZIndex = 72,
}, toolactions.ColorPicker.Frame)
uifactory.Round(toolactions.ColorPicker.Close, 4)

toolactions.ColorPicker.Close.MouseEnter:Connect(function()
    toolactions.ColorPicker.Close.BackgroundTransparency = 0
    toolactions.ColorPicker.Close.BackgroundColor3 = theme.Hover
    toolactions.ColorPicker.Close.TextColor3 = theme.Text
end)

toolactions.ColorPicker.Close.MouseLeave:Connect(function()
    toolactions.ColorPicker.Close.BackgroundTransparency = 1
    toolactions.ColorPicker.Close.TextColor3 = theme.Dim
end)

toolactions.ColorPicker.SVBase = uifactory.Create("Frame", {
    Position = UDim2.fromOffset(12, 40),
    Size = UDim2.fromOffset(190, 150),
    BackgroundColor3 = Color3.fromHSV(0, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Round(toolactions.ColorPicker.SVBase, 4)

toolactions.ColorPicker.SVWhite = uifactory.Create("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 72,
}, toolactions.ColorPicker.SVBase)
uifactory.Round(toolactions.ColorPicker.SVWhite, 4)

uifactory.Create("UIGradient", {
    Rotation = 0,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    }),
}, toolactions.ColorPicker.SVWhite)

toolactions.ColorPicker.SVBlack = uifactory.Create("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BorderSizePixel = 0,
    ZIndex = 73,
}, toolactions.ColorPicker.SVBase)
uifactory.Round(toolactions.ColorPicker.SVBlack, 4)

uifactory.Create("UIGradient", {
    Rotation = 90,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(1, 0),
    }),
}, toolactions.ColorPicker.SVBlack)

toolactions.ColorPicker.SVInput = uifactory.Create("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 74,
}, toolactions.ColorPicker.SVBase)

toolactions.ColorPicker.SVMarker = uifactory.Create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(14, 14),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 75,
}, toolactions.ColorPicker.SVBase)
uifactory.Round(toolactions.ColorPicker.SVMarker, 7)
uifactory.Create("UIStroke", {
    Color = Color3.new(1, 1, 1),
    Thickness = 2,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, toolactions.ColorPicker.SVMarker)

do
    local ring = uifactory.Create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 75,
    }, toolactions.ColorPicker.SVMarker)
    uifactory.Round(ring, 10)
    uifactory.Create("UIStroke", {
        Color = Color3.new(0, 0, 0),
        Thickness = 1,
        Transparency = 0.55,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, ring)
end

toolactions.ColorPicker.Hue = uifactory.Create("Frame", {
    Position = UDim2.fromOffset(212, 40),
    Size = UDim2.fromOffset(16, 150),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Round(toolactions.ColorPicker.Hue, 4)

uifactory.Create("UIGradient", {
    Rotation = 90,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromHSV(0.00, 1, 1)),
        ColorSequenceKeypoint.new(0.16, Color3.fromHSV(0.16, 1, 1)),
        ColorSequenceKeypoint.new(0.33, Color3.fromHSV(0.33, 1, 1)),
        ColorSequenceKeypoint.new(0.50, Color3.fromHSV(0.50, 1, 1)),
        ColorSequenceKeypoint.new(0.66, Color3.fromHSV(0.66, 1, 1)),
        ColorSequenceKeypoint.new(0.83, Color3.fromHSV(0.83, 1, 1)),
        ColorSequenceKeypoint.new(1.00, Color3.fromHSV(1.00, 1, 1)),
    }),
}, toolactions.ColorPicker.Hue)

toolactions.ColorPicker.HueInput = uifactory.Create("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 73,
}, toolactions.ColorPicker.Hue)

toolactions.ColorPicker.HueMarker = uifactory.Create("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0),
    Size = UDim2.fromOffset(22, 8),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 74,
}, toolactions.ColorPicker.Hue)
uifactory.Round(toolactions.ColorPicker.HueMarker, 3)
uifactory.Create("UIStroke", {
    Color = Color3.fromRGB(20, 20, 20),
    Thickness = 1,
    Transparency = 0.35,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, toolactions.ColorPicker.HueMarker)

toolactions.ColorPicker.Preview = uifactory.Create("TextLabel", {
    Position = UDim2.fromOffset(238, 40),
    Size = UDim2.fromOffset(50, 72),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    Text = "New",
    TextColor3 = Color3.fromRGB(20, 20, 20),
    TextSize = 12,
    Font = Enum.Font.SourceSans,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Round(toolactions.ColorPicker.Preview, 4)
uifactory.Stroke(toolactions.ColorPicker.Preview, theme.Border)

toolactions.ColorPicker.Original = uifactory.Create("TextButton", {
    Position = UDim2.fromOffset(238, 118),
    Size = UDim2.fromOffset(50, 72),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "Old",
    TextColor3 = Color3.fromRGB(20, 20, 20),
    TextSize = 12,
    Font = Enum.Font.SourceSans,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Round(toolactions.ColorPicker.Original, 4)
uifactory.Stroke(toolactions.ColorPicker.Original, theme.Border)

toolactions.ColorPicker.CreateField = function(labeltext, x, y, width)
    local label = uifactory.Text(
        toolactions.ColorPicker.Frame,
        labeltext,
        12,
        Enum.TextXAlignment.Left
    )
    label.Position = UDim2.fromOffset(x, y)
    label.Size = UDim2.fromOffset(width, 14)
    label.TextColor3 = theme.Dim
    label.ZIndex = 71

    local box = uifactory.Create("TextBox", {
        Position = UDim2.fromOffset(x, y + 16),
        Size = UDim2.fromOffset(width, 26),
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 14,
        Font = Enum.Font.SourceSans,
        ClearTextOnFocus = false,
        ZIndex = 71,
    }, toolactions.ColorPicker.Frame)
    uifactory.Round(box, 4)

    local stroke = uifactory.Create("UIStroke", {
        Color = theme.BorderSoft,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, box)

    box.Focused:Connect(function()
        stroke.Color = theme.Accent
    end)

    box.FocusLost:Connect(function()
        stroke.Color = theme.BorderSoft
    end)

    return box
end

toolactions.ColorPicker.R = toolactions.ColorPicker.CreateField("R", 12, 198, 88)
toolactions.ColorPicker.G = toolactions.ColorPicker.CreateField("G", 106, 198, 88)
toolactions.ColorPicker.B = toolactions.ColorPicker.CreateField("B", 200, 198, 88)
toolactions.ColorPicker.Hex = toolactions.ColorPicker.CreateField("HEX", 12, 246, 276)

toolactions.ColorPicker.Contrast = function(color)
    local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B

    return luminance > 0.55
        and Color3.fromRGB(20, 20, 20)
        or Color3.fromRGB(245, 245, 245)
end

toolactions.ColorPicker.Refresh = function(updatetext)
    local state = toolactions.ColorPicker.State
    local color = Color3.fromHSV(state.H, state.S, state.V)

    toolactions.ColorPicker.SVBase.BackgroundColor3 =
        Color3.fromHSV(state.H, 1, 1)

    toolactions.ColorPicker.SVMarker.Position =
        UDim2.fromScale(state.S, 1 - state.V)

    toolactions.ColorPicker.HueMarker.Position =
        UDim2.fromScale(0.5, state.H)

    toolactions.ColorPicker.Preview.BackgroundColor3 = color
    toolactions.ColorPicker.Preview.TextColor3 =
        toolactions.ColorPicker.Contrast(color)

    if updatetext ~= false then
        local r = math.floor(color.R * 255 + 0.5)
        local g = math.floor(color.G * 255 + 0.5)
        local b = math.floor(color.B * 255 + 0.5)

        if not toolactions.ColorPicker.R:IsFocused() then
            toolactions.ColorPicker.R.Text = tostring(r)
        end
        if not toolactions.ColorPicker.G:IsFocused() then
            toolactions.ColorPicker.G.Text = tostring(g)
        end
        if not toolactions.ColorPicker.B:IsFocused() then
            toolactions.ColorPicker.B.Text = tostring(b)
        end
        if not toolactions.ColorPicker.Hex:IsFocused() then
            toolactions.ColorPicker.Hex.Text =
                string.format("#%02X%02X%02X", r, g, b)
        end
    end
end

toolactions.ColorPicker.Apply = function()
    local state = toolactions.ColorPicker.State
    local prop = state.Prop

    if not prop then
        return
    end

    toolactions.WriteEntryValue(
        prop,
        Color3.fromHSV(state.H, state.S, state.V),
        false
    )

    if toolactions.RenderProperties then
        toolactions.RenderProperties()
    end
end

toolactions.CloseColorPicker = function()
    toolactions.ColorPicker.Frame.Visible = false
    toolactions.ColorPicker.State.Prop = nil
    toolactions.ColorPicker.State.Row = nil
    toolactions.ColorPicker.State.DragSV = false
    toolactions.ColorPicker.State.DragHue = false
end

main:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
    toolactions.CloseColorPicker()
end)

main:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    toolactions.CloseColorPicker()
end)

toolactions.OpenColorPicker = function(row, prop, color)
    if not row or not prop or prop.ReadOnly or typeof(color) ~= "Color3" then
        return
    end

    propertycontroller.CloseDropdown()

    local h, s, v = color:ToHSV()
    local state = toolactions.ColorPicker.State

    state.Prop = prop
    state.Row = row
    state.H = h
    state.S = s
    state.V = v
    state.Original = color

    toolactions.ColorPicker.Original.BackgroundColor3 = color
    toolactions.ColorPicker.Original.TextColor3 =
        toolactions.ColorPicker.Contrast(color)

    local frame = toolactions.ColorPicker.Frame
    local width = frame.Size.X.Offset
    local height = frame.Size.Y.Offset

    local screen = rootgui.AbsoluteSize
    local mainpos = main.AbsolutePosition
    local mainsize = main.AbsoluteSize
    local gap = 8

    local x = mainpos.X - width - gap

    if x < 4 then
        x = mainpos.X + mainsize.X + gap

        if x + width > screen.X - 4 then
            x = math.max(4, screen.X - width - 4)
        end
    end

    local y = runtimeutil.Clamp(
        row.AbsolutePosition.Y,
        4,
        math.max(4, screen.Y - height - 4)
    )

    frame.Position = UDim2.fromOffset(x, y)
    frame.Visible = true
    toolactions.ColorPicker.Refresh(true)
end

toolactions.ColorPicker.UpdateSV = function(position)
    local input = toolactions.ColorPicker.SVInput
    local x =
        runtimeutil.Clamp(
            (position.X - input.AbsolutePosition.X)
            / math.max(1, input.AbsoluteSize.X),
            0,
            1
        )

    local y =
        runtimeutil.Clamp(
            (position.Y - input.AbsolutePosition.Y)
            / math.max(1, input.AbsoluteSize.Y),
            0,
            1
        )

    toolactions.ColorPicker.State.S = x
    toolactions.ColorPicker.State.V = 1 - y
    toolactions.ColorPicker.Refresh(true)
    toolactions.ColorPicker.Apply()
end

toolactions.ColorPicker.UpdateHue = function(position)
    local input = toolactions.ColorPicker.HueInput

    toolactions.ColorPicker.State.H =
        runtimeutil.Clamp(
            (position.Y - input.AbsolutePosition.Y)
            / math.max(1, input.AbsoluteSize.Y),
            0,
            1
        )

    toolactions.ColorPicker.Refresh(true)
    toolactions.ColorPicker.Apply()
end

toolactions.ColorPicker.SVInput.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        toolactions.ColorPicker.State.DragSV = true
        toolactions.ColorPicker.UpdateSV(input.Position)
    end
end)

toolactions.ColorPicker.HueInput.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        toolactions.ColorPicker.State.DragHue = true
        toolactions.ColorPicker.UpdateHue(input.Position)
    end
end)

uis.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end

    if toolactions.ColorPicker.State.DragSV then
        toolactions.ColorPicker.UpdateSV(input.Position)
    elseif toolactions.ColorPicker.State.DragHue then
        toolactions.ColorPicker.UpdateHue(input.Position)
    end
end)

uis.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        toolactions.ColorPicker.State.DragSV = false
        toolactions.ColorPicker.State.DragHue = false
    end
end)

toolactions.ColorPicker.Close.MouseButton1Click:Connect(function()
    toolactions.CloseColorPicker()
end)

toolactions.ColorPicker.Original.MouseButton1Click:Connect(function()
    local state = toolactions.ColorPicker.State
    local original = state.Original

    if typeof(original) ~= "Color3" then
        return
    end

    state.H, state.S, state.V = original:ToHSV()
    toolactions.ColorPicker.Refresh(true)
    toolactions.ColorPicker.Apply()
end)

toolactions.ColorPicker.ApplyRGB = function()
    local r = tonumber(toolactions.ColorPicker.R.Text)
    local g = tonumber(toolactions.ColorPicker.G.Text)
    local b = tonumber(toolactions.ColorPicker.B.Text)

    if not r or not g or not b then
        toolactions.ColorPicker.Refresh(true)
        return
    end

    local color =
        Color3.fromRGB(
            runtimeutil.Clamp(r, 0, 255),
            runtimeutil.Clamp(g, 0, 255),
            runtimeutil.Clamp(b, 0, 255)
        )

    local h, s, v = color:ToHSV()
    toolactions.ColorPicker.State.H = h
    toolactions.ColorPicker.State.S = s
    toolactions.ColorPicker.State.V = v
    toolactions.ColorPicker.Refresh(true)
    toolactions.ColorPicker.Apply()
end

toolactions.ColorPicker.R.FocusLost:Connect(toolactions.ColorPicker.ApplyRGB)
toolactions.ColorPicker.G.FocusLost:Connect(toolactions.ColorPicker.ApplyRGB)
toolactions.ColorPicker.B.FocusLost:Connect(toolactions.ColorPicker.ApplyRGB)

toolactions.ColorPicker.Hex.FocusLost:Connect(function()
    local raw =
        toolactions.ColorPicker.Hex.Text
        :gsub("#", "")
        :gsub("[^%x]", "")

    if #raw ~= 6 then
        toolactions.ColorPicker.Refresh(true)
        return
    end

    local r = tonumber(raw:sub(1, 2), 16)
    local g = tonumber(raw:sub(3, 4), 16)
    local b = tonumber(raw:sub(5, 6), 16)

    if not r or not g or not b then
        toolactions.ColorPicker.Refresh(true)
        return
    end

    local color = Color3.fromRGB(r, g, b)
    local h, s, v = color:ToHSV()

    toolactions.ColorPicker.State.H = h
    toolactions.ColorPicker.State.S = s
    toolactions.ColorPicker.State.V = v
    toolactions.ColorPicker.Refresh(true)
    toolactions.ColorPicker.Apply()
end)

toolactions.CreatePopup = function(name, title, width, height, z)
    local frame = uifactory.Create("Frame", {
        Name = name,
        Visible = false,
        BackgroundColor3 = Color3.fromRGB(31, 31, 31),
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(width, height),
        ZIndex = z,
    }, rootgui)
    uifactory.Round(frame, 6)
    uifactory.Stroke(frame, theme.Border)

    local titlelabel = uifactory.Text(frame, title, 15)
    titlelabel.Position = UDim2.fromOffset(12, 0)
    titlelabel.Size = UDim2.new(1, -44, 0, 30)
    titlelabel.ZIndex = z + 1

    uifactory.Create("Frame", {
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = theme.BorderSoft,
        BorderSizePixel = 0,
        ZIndex = z + 1,
    }, frame)

    local close = uifactory.Create("TextButton", {
        Position = UDim2.new(1, -30, 0, 2),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "×",
        TextColor3 = theme.Dim,
        TextSize = 18,
        Font = Enum.Font.SourceSans,
        ZIndex = z + 2,
    }, frame)
    uifactory.Round(close, 4)

    close.MouseEnter:Connect(function()
        close.BackgroundTransparency = 0
        close.BackgroundColor3 = theme.Hover
        close.TextColor3 = theme.Text
    end)

    close.MouseLeave:Connect(function()
        close.BackgroundTransparency = 1
        close.TextColor3 = theme.Dim
    end)

    return frame, titlelabel, close
end

toolactions.PlacePopup = function(frame, anchor)
    local width = frame.Size.X.Offset
    local height = frame.Size.Y.Offset
    local screen = rootgui.AbsoluteSize
    local mainpos = main.AbsolutePosition
    local mainsize = main.AbsoluteSize
    local gap = 8

    local x = mainpos.X - width - gap

    if x < 4 then
        x = mainpos.X + mainsize.X + gap

        if x + width > screen.X - 4 then
            x = math.max(4, screen.X - width - 4)
        end
    end

    local y = runtimeutil.Clamp(
        anchor and anchor.AbsolutePosition.Y or 40,
        4,
        math.max(4, screen.Y - height - 4)
    )

    frame.Position = UDim2.fromOffset(x, y)
end

toolactions.CreateEditorBox = function(parent, x, y, width, height, z)
    local box = uifactory.Create("TextBox", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 14,
        Font = Enum.Font.SourceSans,
        ClearTextOnFocus = false,
        ZIndex = z,
    }, parent)
    uifactory.Round(box, 4)

    local stroke = uifactory.Create("UIStroke", {
        Color = theme.BorderSoft,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, box)

    box.Focused:Connect(function()
        stroke.Color = theme.Accent
    end)

    box.FocusLost:Connect(function()
        stroke.Color = theme.BorderSoft
    end)

    return box, stroke
end

toolactions.CreateEditorButton = function(parent, text, x, y, width, height, z)
    local button = uifactory.Create("TextButton", {
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = theme.Panel3,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = text,
        TextColor3 = theme.Text,
        TextSize = 14,
        Font = Enum.Font.SourceSans,
        ZIndex = z,
    }, parent)
    uifactory.Round(button, 4)

    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = theme.Hover
    end)

    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = theme.Panel3
    end)

    return button
end

-- NumberSequence / ColorSequence editor
do
    local SE = {
        Prop = nil,
        Type = nil,
        Rows = {},
        Markers = {},
        Bars = {},
        Selected = 1,
        Drag = nil,
        MinV = 0,
        MaxV = 1,
        Accum = 0,
    }
    toolactions.SequenceEditor = SE

    local BAR_COUNT = 48
    local ROW_H = 28

    SE.Frame, SE.Title, SE.Close = toolactions.CreatePopup("SequenceEditor", "Sequence", 344, 392, 60)
    local frame = SE.Frame

    SE.Graph = uifactory.Create("TextButton", {
        Position = UDim2.fromOffset(12, 42),
        Size = UDim2.fromOffset(320, 96),
        BackgroundColor3 = Color3.fromRGB(22, 22, 22),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 61,
    }, frame)
    uifactory.Stroke(SE.Graph, theme.Border)

    SE.BarHolder = uifactory.Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 62,
    }, SE.Graph)

    for i = 1, BAR_COUNT do
        SE.Bars[i] = uifactory.Create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new((i - 1) / BAR_COUNT, 0, 1, 0),
            Size = UDim2.new(1 / BAR_COUNT, 0, 0, 0),
            BackgroundColor3 = Color3.fromRGB(58, 118, 176),
            BorderSizePixel = 0,
            ZIndex = 62,
        }, SE.BarHolder)
    end

    SE.Gradient = uifactory.Create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        ZIndex = 62,
    }, SE.Graph)

    SE.GradientObject = uifactory.Create("UIGradient", {}, SE.Gradient)

    SE.AddButton = toolactions.CreateEditorButton(frame, "+ Add Key", 12, 146, 90, 24, 61)

    SE.Hint = uifactory.Text(frame, "click graph to add • drag points", 12)
    SE.Hint.Position = UDim2.fromOffset(110, 146)
    SE.Hint.Size = UDim2.fromOffset(222, 24)
    SE.Hint.TextColor3 = theme.Dim
    SE.Hint.ZIndex = 61

    SE.Header = uifactory.Text(frame, "", 12)
    SE.Header.Position = UDim2.fromOffset(12, 176)
    SE.Header.Size = UDim2.fromOffset(320, 16)
    SE.Header.TextColor3 = theme.Dim
    SE.Header.ZIndex = 61

    SE.List = uifactory.Create("ScrollingFrame", {
        Position = UDim2.fromOffset(12, 196),
        Size = UDim2.fromOffset(320, 184),
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = Color3.fromRGB(92, 92, 92),
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 61,
    }, frame)
    uifactory.Stroke(SE.List, theme.BorderSoft)

    local function readkeys(value)
        local out = {}
        local isnumber = typeof(value) == "NumberSequence"

        for _, kp in value.Keypoints do
            if isnumber then
                out[#out + 1] = {Time = kp.Time, Value = kp.Value, Envelope = kp.Envelope}
            else
                out[#out + 1] = {Time = kp.Time, Color = kp.Value}
            end
        end

        return out
    end

    local function sample(list, isnumber, t)
        for i = 1, #list - 1 do
            local a = list[i]
            local b = list[i + 1]

            if t >= a.Time and t <= b.Time then
                local span = b.Time - a.Time
                local f = span > 0 and (t - a.Time) / span or 0

                if isnumber then
                    return a.Value + (b.Value - a.Value) * f, a.Envelope + (b.Envelope - a.Envelope) * f
                end

                return a.Color:Lerp(b.Color, f)
            end
        end

        local last = list[#list]

        if isnumber then
            return last.Value, last.Envelope
        end

        return last.Color
    end

    local function normalize(list)
        table.sort(list, function(a, b)
            return a.Time < b.Time
        end)

        list[1].Time = 0
        list[#list].Time = 1

        for i = 2, #list - 1 do
            local t = math.max(list[i].Time, list[i - 1].Time + 0.001)
            list[i].Time = math.min(t, 1 - 0.001 * (#list - i))
        end
    end

    local function commit(list, structural)
        local isnumber = SE.Type == "NumberSequence"

        normalize(list)

        local ok, sequence = pcall(function()
            local points = {}

            for i, k in list do
                if isnumber then
                    points[i] = NumberSequenceKeypoint.new(k.Time, k.Value, math.max(0, k.Envelope or 0))
                else
                    points[i] = ColorSequenceKeypoint.new(k.Time, k.Color)
                end
            end

            if isnumber then
                return NumberSequence.new(points)
            end

            return ColorSequence.new(points)
        end)

        if ok and sequence then
            valuecodec.WriteProperty(SE.Prop, sequence, structural == true)
        end

        SE.Refresh()
    end

    SE.Read = function()
        if not SE.Prop then
            return nil
        end

        local value, readable = toolactions.ReadBasePropertyValue(SE.Prop)

        if readable and typeof(value) == SE.Type then
            return value
        end

        return nil
    end

    local function edit(index, fn, structural)
        local value = SE.Read()

        if not value then
            return
        end

        local list = readkeys(value)

        if not list[index] then
            return
        end

        fn(list[index], list)
        commit(list, structural)
    end

    SE.GetMarker = function(i)
        local marker = SE.Markers[i]

        if marker then
            return marker
        end

        marker = uifactory.Create("TextButton", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(12, 12),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            ZIndex = 66,
        }, SE.Graph)
        uifactory.Round(marker, 6)
        uifactory.Stroke(marker, Color3.fromRGB(20, 20, 20))

        marker.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                SE.Selected = i
                SE.Drag = i
                SE.Refresh()
            end
        end)

        SE.Markers[i] = marker
        return marker
    end

    SE.GetRow = function(i)
        local row = SE.Rows[i]

        if row then
            return row
        end

        local root = uifactory.Create("Frame", {
            Position = UDim2.fromOffset(0, (i - 1) * ROW_H),
            Size = UDim2.new(1, -8, 0, ROW_H),
            BackgroundColor3 = theme.Panel,
            BorderSizePixel = 0,
            ZIndex = 62,
        }, SE.List)

        local index = uifactory.Text(root, tostring(i), 13, Enum.TextXAlignment.Center)
        index.Position = UDim2.fromOffset(0, 0)
        index.Size = UDim2.fromOffset(22, ROW_H)
        index.TextColor3 = theme.Dim
        index.ZIndex = 63

        local time = toolactions.CreateEditorBox(root, 24, 2, 62, ROW_H - 4, 63)
        local value = toolactions.CreateEditorBox(root, 92, 2, 76, ROW_H - 4, 63)
        local envelope = toolactions.CreateEditorBox(root, 174, 2, 62, ROW_H - 4, 63)

        local swatch = uifactory.Create("TextButton", {
            Position = UDim2.fromOffset(92, 4),
            Size = UDim2.fromOffset(28, ROW_H - 8),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            ZIndex = 63,
        }, root)
        uifactory.Stroke(swatch, Color3.fromRGB(120, 120, 120))

        local rgb = toolactions.CreateEditorBox(root, 126, 2, 110, ROW_H - 4, 63)

        local delete = toolactions.CreateEditorButton(root, "×", 246, 2, 26, ROW_H - 4, 63)
        delete.TextSize = 18

        root.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                SE.Selected = i
            end
        end)

        time.FocusLost:Connect(function()
            local n = tonumber(time.Text)

            if n then
                edit(i, function(k)
                    k.Time = runtimeutil.Clamp(n, 0, 1)
                end)
            else
                SE.Refresh()
            end
        end)

        value.FocusLost:Connect(function()
            local n = tonumber(value.Text)

            if n then
                edit(i, function(k)
                    k.Value = n
                end)
            else
                SE.Refresh()
            end
        end)

        envelope.FocusLost:Connect(function()
            local n = tonumber(envelope.Text)

            if n then
                edit(i, function(k)
                    k.Envelope = math.max(0, n)
                end)
            else
                SE.Refresh()
            end
        end)

        rgb.FocusLost:Connect(function()
            local color, ok = valuecodec.Parse(rgb.Text, "Color3")

            if ok then
                edit(i, function(k)
                    k.Color = color
                end)
            else
                SE.Refresh()
            end
        end)

        swatch.MouseButton1Click:Connect(function()
            local sequence = SE.Read()
            local list = sequence and readkeys(sequence)
            local key = list and list[i]

            if not key or not key.Color then
                return
            end

            toolactions.OpenColorPicker(swatch, {
                Name = "Color",
                Category = "Sequence",
                ValueType = "Color3",
                Special = "Component",
                ComponentKey = "CS:" .. i .. ":Color",
                ParentProp = SE.Prop,
                ReadOnly = false,
            }, key.Color)

            local picker = toolactions.ColorPicker.Frame
            local pickerx = SE.Frame.AbsolutePosition.X - picker.Size.X.Offset - 8

            if pickerx >= 4 then
                picker.Position = UDim2.fromOffset(pickerx, SE.Frame.AbsolutePosition.Y)
            end
        end)

        delete.MouseButton1Click:Connect(function()
            edit(i, function(_, list)
                if #list > 2 and i ~= 1 and i ~= #list then
                    table.remove(list, i)
                end
            end, true)
        end)

        row = {
            Root = root,
            Index = index,
            Time = time,
            Value = value,
            Envelope = envelope,
            Swatch = swatch,
            RGB = rgb,
            Delete = delete,
        }

        SE.Rows[i] = row
        return row
    end

    SE.Refresh = function()
        local value = SE.Read()

        if not value then
            toolactions.CloseSequenceEditor()
            return
        end

        local isnumber = SE.Type == "NumberSequence"
        local list = readkeys(value)

        if not SE.Drag then
            local hi = 1
            local lo = 0

            if isnumber then
                for _, k in list do
                    hi = math.max(hi, k.Value + k.Envelope)
                    lo = math.min(lo, k.Value - k.Envelope)
                end
            end

            SE.MinV = lo
            SE.MaxV = hi
        end

        local range = math.max(1e-6, SE.MaxV - SE.MinV)

        SE.BarHolder.Visible = isnumber
        SE.Gradient.Visible = not isnumber

        if isnumber then
            for i, bar in SE.Bars do
                local v = sample(list, true, (i - 0.5) / BAR_COUNT)
                local frac = runtimeutil.Clamp((v - SE.MinV) / range, 0, 1)
                bar.Size = UDim2.new(1 / BAR_COUNT, 0, frac, 0)
            end
        else
            SE.GradientObject.Color = value
        end

        SE.Selected = runtimeutil.Clamp(SE.Selected, 1, #list)
        SE.Header.Text = isnumber
            and "    #     Time          Value          Envelope"
            or "    #     Time          Color"

        for i, key in list do
            local marker = SE.GetMarker(i)
            local y = 0.5

            if isnumber then
                y = 1 - runtimeutil.Clamp((key.Value - SE.MinV) / range, 0, 1)
            end

            marker.Visible = true
            marker.Position = UDim2.new(key.Time, 0, y, 0)
            marker.BackgroundColor3 = isnumber and Color3.new(1, 1, 1) or key.Color
            marker.Size = i == SE.Selected and UDim2.fromOffset(14, 14) or UDim2.fromOffset(12, 12)
        end

        for i = #list + 1, #SE.Markers do
            SE.Markers[i].Visible = false
        end

        for i, key in list do
            local row = SE.GetRow(i)

            row.Root.Visible = true
            row.Root.Position = UDim2.fromOffset(0, (i - 1) * ROW_H)
            row.Root.BackgroundColor3 = i == SE.Selected and theme.Hover or theme.Panel
            row.Value.Visible = isnumber
            row.Envelope.Visible = isnumber
            row.Swatch.Visible = not isnumber
            row.RGB.Visible = not isnumber
            row.Delete.Visible = #list > 2 and i ~= 1 and i ~= #list

            local function settext(box, text)
                if not box:IsFocused() and box.Text ~= text then
                    box.Text = text
                end
            end

            settext(row.Time, ("%.3f"):format(key.Time))

            if isnumber then
                settext(row.Value, ("%.3f"):format(key.Value))
                settext(row.Envelope, ("%.3f"):format(key.Envelope))
            else
                row.Swatch.BackgroundColor3 = key.Color
                settext(row.RGB, valuecodec.ToString(key.Color))
            end
        end

        for i = #list + 1, #SE.Rows do
            SE.Rows[i].Root.Visible = false
        end

        SE.List.CanvasSize = UDim2.fromOffset(0, #list * ROW_H)
    end

    SE.AddKeyAt = function(time)
        local value = SE.Read()

        if not value then
            return
        end

        local isnumber = SE.Type == "NumberSequence"
        local list = readkeys(value)
        local key = {Time = runtimeutil.Clamp(time, 0.001, 0.999)}

        if isnumber then
            key.Value, key.Envelope = sample(list, true, key.Time)
        else
            key.Color = sample(list, false, key.Time)
        end

        list[#list + 1] = key
        SE.Selected = #list
        commit(list, true)
    end

    SE.AddButton.MouseButton1Click:Connect(function()
        local value = SE.Read()

        if not value then
            return
        end

        local list = readkeys(value)
        local bestgap = 0
        local besttime = 0.5

        for i = 1, #list - 1 do
            local gap = list[i + 1].Time - list[i].Time

            if gap > bestgap then
                bestgap = gap
                besttime = list[i].Time + gap / 2
            end
        end

        SE.AddKeyAt(besttime)
    end)

    SE.Graph.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        local fx = (input.Position.X - SE.Graph.AbsolutePosition.X) / math.max(1, SE.Graph.AbsoluteSize.X)
        SE.AddKeyAt(fx)
    end)

    uis.InputChanged:Connect(function(input)
        if not SE.Drag or input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end

        local graph = SE.Graph
        local fx = runtimeutil.Clamp((input.Position.X - graph.AbsolutePosition.X) / math.max(1, graph.AbsoluteSize.X), 0, 1)
        local fy = runtimeutil.Clamp((input.Position.Y - graph.AbsolutePosition.Y) / math.max(1, graph.AbsoluteSize.Y), 0, 1)
        local isnumber = SE.Type == "NumberSequence"
        local index = SE.Drag

        edit(index, function(k, list)
            if index ~= 1 and index ~= #list then
                local lo = list[index - 1].Time + 0.001
                local hi = list[index + 1].Time - 0.001
                k.Time = math.floor(runtimeutil.Clamp(fx, lo, math.max(lo, hi)) * 1000 + 0.5) / 1000
            end

            if isnumber then
                k.Value = math.floor((SE.MinV + (1 - fy) * (SE.MaxV - SE.MinV)) * 1000 + 0.5) / 1000
            end
        end)
    end)

    uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            SE.Drag = nil
        end
    end)

    toolactions.CloseSequenceEditor = function()
        frame.Visible = false
        SE.Prop = nil
        SE.Type = nil
        SE.Drag = nil
    end

    toolactions.OpenSequenceEditor = function(row, prop, value)
        local t = typeof(value)

        if (t ~= "NumberSequence" and t ~= "ColorSequence") or not prop or prop.ReadOnly then
            return
        end

        propertycontroller.CloseDropdown()
        toolactions.CloseColorPicker()
        toolactions.ClosePropertyMenu()

        if toolactions.CloseBrickPalette then toolactions.CloseBrickPalette() end
        if toolactions.CloseAttributeDialog then toolactions.CloseAttributeDialog() end

        SE.Prop = prop
        SE.Type = t
        SE.Selected = 1
        SE.Drag = nil
        SE.Title.Text = t .. " • " .. tostring(prop.Name)

        toolactions.PlacePopup(frame, row)
        frame.Visible = true
        SE.Refresh()
    end

    SE.Close.MouseButton1Click:Connect(toolactions.CloseSequenceEditor)

    runservice.Heartbeat:Connect(function(dt)
        if not frame.Visible or not rootgui.Parent then
            return
        end

        SE.Accum += dt

        if SE.Accum < 0.1 then
            return
        end

        SE.Accum = 0
        SE.Refresh()
    end)
end

-- BrickColor palette
do
    local BP = {
        Cells = {},
        Prop = nil,
        Built = false,
    }
    toolactions.BrickPalette = BP

    local COLUMNS = 10
    local CELL = 27

    BP.Frame, BP.Title, BP.Close = toolactions.CreatePopup("BrickPalette", "BrickColor", 296, 322, 60)
    local frame = BP.Frame

    BP.Scroll = uifactory.Create("ScrollingFrame", {
        Position = UDim2.fromOffset(8, 38),
        Size = UDim2.fromOffset(280, 246),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 6,
        ScrollBarImageColor3 = Color3.fromRGB(92, 92, 92),
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 61,
    }, frame)

    BP.Name = uifactory.Text(frame, "", 15)
    BP.Name.Position = UDim2.fromOffset(12, 290)
    BP.Name.Size = UDim2.fromOffset(272, 24)
    BP.Name.ZIndex = 61

    BP.Build = function()
        if BP.Built then
            return
        end

        BP.Built = true

        local seen = {}
        local index = 0

        for paletteindex = 0, 127 do
            local ok, bc = pcall(BrickColor.palette, paletteindex)

            if ok and typeof(bc) == "BrickColor" and not seen[bc.Number] then
                seen[bc.Number] = true

                local col = index % COLUMNS
                local rowindex = math.floor(index / COLUMNS)

                local cell = uifactory.Create("TextButton", {
                    Position = UDim2.fromOffset(col * CELL + 2, rowindex * CELL + 2),
                    Size = UDim2.fromOffset(CELL - 3, CELL - 3),
                    BackgroundColor3 = bc.Color,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = "",
                    ZIndex = 62,
                }, BP.Scroll)
                uifactory.Round(cell, 3)

                local stroke = uifactory.Create("UIStroke", {
                    Color = Color3.fromRGB(60, 60, 60),
                    Thickness = 1,
                    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
                }, cell)

                cell.MouseEnter:Connect(function()
                    BP.Name.Text = tostring(bc)
                end)

                cell.MouseButton1Click:Connect(function()
                    if BP.Prop then
                        toolactions.WriteEntryValue(BP.Prop, bc)
                    end

                    toolactions.CloseBrickPalette()
                end)

                BP.Cells[#BP.Cells + 1] = {Cell = cell, Stroke = stroke, Number = bc.Number}
                index += 1
            end
        end

        BP.Scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(index / COLUMNS) * CELL + 4)
    end

    toolactions.CloseBrickPalette = function()
        frame.Visible = false
        BP.Prop = nil
    end

    toolactions.OpenBrickPalette = function(row, prop, current)
        if not prop or prop.ReadOnly or typeof(current) ~= "BrickColor" then
            return
        end

        propertycontroller.CloseDropdown()
        toolactions.CloseColorPicker()
        toolactions.ClosePropertyMenu()

        if toolactions.CloseSequenceEditor then toolactions.CloseSequenceEditor() end
        if toolactions.CloseAttributeDialog then toolactions.CloseAttributeDialog() end

        BP.Build()
        BP.Prop = prop
        BP.Name.Text = tostring(current)

        for _, entry in BP.Cells do
            local selected = entry.Number == current.Number
            entry.Stroke.Color = selected and theme.Accent or Color3.fromRGB(60, 60, 60)
            entry.Stroke.Thickness = selected and 2 or 1
        end

        toolactions.PlacePopup(frame, row)
        frame.Visible = true
    end

    BP.Close.MouseButton1Click:Connect(toolactions.CloseBrickPalette)

    uis.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not frame.Visible then
            return
        end

        local mouse = uis:GetMouseLocation()

        if toolactions.PointInside(frame, mouse) or toolactions.PointInside(propscroll, mouse) then
            return
        end

        toolactions.CloseBrickPalette()
    end)

    propscroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if frame.Visible then
            toolactions.CloseBrickPalette()
        end
    end)
end

-- Add Attribute / Add Tag dialog
do
    local AD = {
        Mode = nil,
        Type = "string",
        TypeButtons = {},
    }
    toolactions.AddDialog = AD

    local TYPES = {
        {"string", function() return "" end},
        {"number", function() return 0 end},
        {"boolean", function() return false end},
        {"Vector2", function() return Vector2.new(0, 0) end},
        {"Vector3", function() return Vector3.new(0, 0, 0) end},
        {"UDim", function() return UDim.new(0, 0) end},
        {"UDim2", function() return UDim2.new(0, 0, 0, 0) end},
        {"Color3", function() return Color3.new(1, 1, 1) end},
        {"BrickColor", function() return BrickColor.new("Medium stone grey") end},
        {"Rect", function() return Rect.new(0, 0, 0, 0) end},
        {"NumberRange", function() return NumberRange.new(0, 1) end},
        {"NumberSequence", function() return NumberSequence.new(0, 1) end},
        {"ColorSequence", function() return ColorSequence.new(Color3.new(1, 1, 1)) end},
    }

    AD.Frame, AD.Title, AD.Close = toolactions.CreatePopup("AddDialog", "Add Attribute", 268, 232, 60)
    local frame = AD.Frame

    AD.NameBox, AD.NameStroke = toolactions.CreateEditorBox(frame, 12, 40, 244, 26, 61)
    AD.NameBox.PlaceholderText = "Name"
    AD.NameBox.PlaceholderColor3 = Color3.fromRGB(125, 125, 125)

    AD.Types = uifactory.Create("Frame", {
        Position = UDim2.fromOffset(12, 74),
        Size = UDim2.fromOffset(244, 118),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, frame)

    uifactory.Create("UIGridLayout", {
        CellSize = UDim2.fromOffset(78, 22),
        CellPadding = UDim2.fromOffset(5, 5),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, AD.Types)

    AD.AddButton = toolactions.CreateEditorButton(frame, "Add", 12, 0, 244, 28, 61)
    AD.AddButton.AnchorPoint = Vector2.new(0, 1)
    AD.AddButton.Position = UDim2.new(0, 12, 1, -10)
    AD.AddButton.BackgroundColor3 = Color3.fromRGB(47, 83, 112)

    AD.SelectType = function(name)
        AD.Type = name

        for typename, button in AD.TypeButtons do
            button.BackgroundColor3 = typename == name and Color3.fromRGB(47, 83, 112) or theme.Panel3
        end
    end

    for order, entry in TYPES do
        local button = toolactions.CreateEditorButton(AD.Types, entry[1], 0, 0, 78, 22, 62)
        button.LayoutOrder = order
        button.TextSize = 13
        AD.TypeButtons[entry[1]] = button

        button.MouseButton1Click:Connect(function()
            AD.SelectType(entry[1])
        end)
    end

    AD.Defaults = {}

    for _, entry in TYPES do
        AD.Defaults[entry[1]] = entry[2]
    end

    AD.Flash = function()
        AD.NameStroke.Color = theme.Danger

        task.delay(0.8, function()
            if AD.NameStroke.Parent then
                AD.NameStroke.Color = theme.BorderSoft
            end
        end)
    end

    AD.Submit = function()
        local obj = selectednode and selectednode.obj
        local name = runtimeutil.Trim(AD.NameBox.Text)

        if typeof(obj) ~= "Instance" or name == "" then
            AD.Flash()
            return
        end

        local ok

        if AD.Mode == "Attribute" then
            if obj:GetAttribute(name) ~= nil then
                AD.Flash()
                return
            end

            ok = pcall(obj.SetAttribute, obj, name, AD.Defaults[AD.Type]())
        else
            ok = pcall(obj.AddTag, obj, name)
        end

        if not ok then
            AD.Flash()
            return
        end

        toolactions.CloseAttributeDialog()
        propertycontroller.Rebuild()
        propertycontroller.Render()
    end

    AD.AddButton.MouseButton1Click:Connect(AD.Submit)

    AD.NameBox.FocusLost:Connect(function(enter)
        if enter then
            AD.Submit()
        end
    end)

    toolactions.CloseAttributeDialog = function()
        frame.Visible = false
        AD.NameBox.Text = ""
        AD.Mode = nil
    end

    toolactions.OpenAddDialog = function(mode, row)
        propertycontroller.CloseDropdown()
        toolactions.CloseColorPicker()
        toolactions.ClosePropertyMenu()

        if toolactions.CloseSequenceEditor then toolactions.CloseSequenceEditor() end
        if toolactions.CloseBrickPalette then toolactions.CloseBrickPalette() end

        AD.Mode = mode
        AD.NameBox.Text = ""
        AD.Title.Text = mode == "Attribute" and "Add Attribute" or "Add Tag"
        AD.Types.Visible = mode == "Attribute"
        frame.Size = UDim2.fromOffset(268, mode == "Attribute" and 232 or 116)
        AD.SelectType(AD.Type)

        toolactions.PlacePopup(frame, row)
        frame.Visible = true
        AD.NameBox:CaptureFocus()
    end

    AD.Close.MouseButton1Click:Connect(toolactions.CloseAttributeDialog)
end

main:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
    toolactions.CloseSequenceEditor()
    toolactions.CloseBrickPalette()
    toolactions.CloseAttributeDialog()
end)

-- Credits
do
    toolactions.Credits = {"SixZensED"}

    local button = uifactory.Create("ImageButton", {
        Name = "Developer",
        AutoButtonColor = false,
        BackgroundTransparency = 0,
        BackgroundColor3 = Color3.fromRGB(34, 34, 34),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(28, 28),
        Image = "",
        ZIndex = topbuttons.ZIndex + 1,
    }, topbuttons)

    local icon = uifactory.Create("ImageLabel", {
        Name = "Icon",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(15, 15),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = "rbxassetid://124869839333139",
        ImageColor3 = Color3.fromRGB(235, 235, 235),
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = button.ZIndex + 1,
    }, button)

    local frame = uifactory.Create("Frame", {
        Name = "DeveloperPage",
        Visible = false,
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 1, -28),
        Active = true,
        ZIndex = 60,
    }, main)
    toolactions.CreditsFrame = frame

    local header = uifactory.Create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, frame)

    local title = uifactory.Text(header, "Developer", 16)
    title.Position = UDim2.fromOffset(8, 0)
    title.Size = UDim2.new(1, -16, 1, 0)
    title.ZIndex = 62

    local content = uifactory.Create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 1, -28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 7,
        ScrollBarImageColor3 = Color3.fromRGB(92, 92, 92),
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ElasticBehavior = Enum.ElasticBehavior.Never,
        ZIndex = 61,
    }, frame)

    local y = 8

    for _, entry in toolactions.Credits do
        local name = uifactory.Text(content, entry, 18)
        name.Position = UDim2.fromOffset(14, y)
        name.Size = UDim2.new(1, -28, 0, 26)
        name.TextColor3 = theme.Accent2
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.ZIndex = 62

        y += 32
    end

    content.CanvasSize = UDim2.fromOffset(0, y + 8)

    local function setactive(active)
        button.BackgroundColor3 = active and Color3.fromRGB(50, 53, 59) or Color3.fromRGB(34, 34, 34)
        icon.ImageColor3 = active and theme.Accent or Color3.fromRGB(235, 235, 235)
    end

    toolactions.CloseCredits = function()
        frame.Visible = false
        setactive(false)
    end

    toolactions.OpenCredits = function()
        propertycontroller.CloseDropdown()
        toolactions.CloseColorPicker()
        toolactions.ClosePropertyMenu()
        menucontroller.Close()

        if toolactions.Settings.Close then
            toolactions.Settings.Close()
        end

        frame.Visible = true
        setactive(true)
    end

    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
        icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
    end)

    button.MouseLeave:Connect(function()
        setactive(frame.Visible)
    end)

    button.MouseButton1Click:Connect(function()
        if frame.Visible then
            toolactions.CloseCredits()
        else
            toolactions.OpenCredits()
        end
    end)
end

toolactions.PropertyMenu = toolactions.PropertyMenu or {}
toolactions.PropertyMenu.Frame = uifactory.Create("Frame", {
    Name = "PropertyMenu",
    Visible = false,
    BackgroundColor3 = Color3.fromRGB(28, 29, 32),
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(160, 28),
    ZIndex = 80,
}, propertiespane)
uifactory.Stroke(toolactions.PropertyMenu.Frame, theme.Border)

toolactions.PropertyMenu.Reset = uifactory.Create("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "Reset Property",
    TextColor3 = theme.Text,
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    ZIndex = 81,
}, toolactions.PropertyMenu.Frame)

toolactions.PropertyMenu.Delete = uifactory.Create("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "Delete Attribute",
    TextColor3 = Color3.fromRGB(235, 120, 120),
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    Visible = false,
    ZIndex = 81,
}, toolactions.PropertyMenu.Frame)

toolactions.PropertyMenu.Prop = nil

toolactions.ClosePropertyMenu = function()
    toolactions.PropertyMenu.Frame.Visible = false
    toolactions.PropertyMenu.Prop = nil
end

toolactions.GetDefaultPropertyValue = function(prop)
    if not selectednode or not selectednode.obj or not prop then
        return nil, false
    end

    local base = prop.ParentProp or prop

    if base.Special == "Attribute"
        or base.Special == "Category"
    then
        return nil, false
    end

    local ok, instance =
        pcall(Instance.new, selectednode.obj.ClassName)

    if not ok or not instance then
        return nil, false
    end

    local value, readable = valuecodec.ReadProperty(instance, base.Name)

    pcall(function()
        instance:Destroy()
    end)

    return value, readable
end

toolactions.ResetProperty = function(prop)
    local base = prop and (prop.ParentProp or prop)

    if not base or base.ReadOnly then
        return false
    end

    local value, ok = toolactions.GetDefaultPropertyValue(base)

    if not ok then
        return false
    end

    return valuecodec.WriteProperty(base, value)
end

toolactions.OpenPropertyMenu = function(row, prop, position)
    if not row or not prop then
        return
    end

    local base = prop.ParentProp or prop
    local isattribute = base.Special == "Attribute"
    local istag = base.Special == "Tag"

    if base.Special == "Category"
        or base.Special == "Action"
        or (base.ReadOnly and not istag)
    then
        return
    end

    toolactions.PropertyMenu.Reset.Visible = not (isattribute or istag)
    toolactions.PropertyMenu.Delete.Visible = isattribute or istag
    toolactions.PropertyMenu.Delete.Text = istag and "Remove Tag" or "Delete Attribute"

    propertycontroller.CloseDropdown()
    toolactions.CloseColorPicker()

    local menu = toolactions.PropertyMenu.Frame
    local x =
        position.X
        - propertiespane.AbsolutePosition.X

    local y =
        position.Y
        - propertiespane.AbsolutePosition.Y

    x =
        runtimeutil.Clamp(
            x,
            0,
            math.max(0, propertiespane.AbsoluteSize.X - menu.Size.X.Offset)
        )

    y =
        runtimeutil.Clamp(
            y,
            0,
            math.max(0, propertiespane.AbsoluteSize.Y - menu.Size.Y.Offset)
        )

    toolactions.PropertyMenu.Prop = base
    menu.Position = UDim2.fromOffset(x, y)
    menu.Visible = true
end

toolactions.PropertyMenu.Reset.MouseButton1Click:Connect(function()
    local prop = toolactions.PropertyMenu.Prop

    if prop then
        toolactions.ResetProperty(prop)
    end

    toolactions.ClosePropertyMenu()
end)

toolactions.PropertyMenu.Delete.MouseButton1Click:Connect(function()
    local prop = toolactions.PropertyMenu.Prop
    local obj = selectednode and selectednode.obj

    if prop and typeof(obj) == "Instance" then
        if prop.Special == "Attribute" then
            pcall(obj.SetAttribute, obj, prop.AttrName, nil)
        elseif prop.Special == "Tag" then
            pcall(obj.RemoveTag, obj, prop.TagName)
        end

        propertycontroller.Rebuild()
        propertycontroller.Render()
    end

    toolactions.ClosePropertyMenu()
end)

toolactions.PropertyCategoryCollapsed =
    toolactions.PropertyCategoryCollapsed or {}

function propertycontroller.CreateRow(i: number)
    local row = uifactory.Create("Frame", {
        Size = UDim2.fromOffset(propertycontroller.GetCanvasWidth(), prop_h),
        BackgroundColor3 = theme.Panel,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Visible = false,
    }, propscroll)

    local expandbutton = uifactory.Create("TextButton", {
        Name = "ExpandButton",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(2, 0),
        Size = UDim2.fromOffset(18, prop_h),
        Text = "▶",
        TextColor3 = theme.Dim,
        TextSize = 12,
        Font = Enum.Font.SourceSansBold,
        Visible = false,
        ZIndex = 5,
    }, row)

    local name = uifactory.Text(row, "", 16)
    name.Size = UDim2.fromOffset(prop_name_w - 10, prop_h)
    name.Position = UDim2.fromOffset(5, 0)
    name.TextTruncate = Enum.TextTruncate.AtEnd

    local sep = uifactory.Create("Frame", {
        Position = UDim2.fromOffset(prop_name_w, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = theme.BorderSoft,
        BorderSizePixel = 0,
    }, row)

    local value = uifactory.Create("TextBox", {
        Position = UDim2.fromOffset(prop_name_w + 4, 1),
        Size = UDim2.fromOffset(
            math.max(120, propertycontroller.GetCanvasWidth() - prop_name_w - 9),
            prop_h - 2
        ),
        BackgroundColor3 = theme.Panel,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Text = "",
        TextColor3 = theme.Text,
        TextSize = 16,
        Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    uifactory.Create("UIPadding", {PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4)}, value)

    local boolbox = uifactory.Create("TextButton", {
        Name = "BoolBox",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.fromRGB(35, 37, 41),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(prop_name_w + 8, 4),
        Size = UDim2.fromOffset(17, 17),
        Text = "",
        TextColor3 = Color3.fromRGB(25, 25, 25),
        TextSize = 16,
        Font = Enum.Font.SourceSansBold,
        Visible = false,
        ZIndex = 4,
    }, row)
    uifactory.Round(boolbox, 1)
    uifactory.Stroke(boolbox, Color3.fromRGB(105, 108, 114))

    local colorswatch = uifactory.Create("TextButton", {
        Name = "ColorSwatch",
        AutoButtonColor = false,
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(prop_name_w + 8, 5),
        Size = UDim2.fromOffset(16, 16),
        Text = "",
        Visible = false,
        ZIndex = 4,
    }, row)
    uifactory.Stroke(colorswatch, Color3.fromRGB(120, 120, 120))

    local refbutton = uifactory.Create("TextButton", {
        Name = "RefButton",
        AutoButtonColor = false,
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(propertycontroller.GetVisibleRight() - 24, 1),
        Size = UDim2.fromOffset(20, prop_h - 2),
        Text = "↗",
        TextColor3 = theme.Text,
        TextSize = 14,
        Font = Enum.Font.SourceSansBold,
        Visible = false,
        ZIndex = 5,
    }, row)
    uifactory.Stroke(refbutton, theme.BorderSoft)

    local dropbutton = uifactory.Create("TextButton", {
        Name = "DropButton",
        AutoButtonColor = false,
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(propertycontroller.GetVisibleRight() - 24, 1),
        Size = UDim2.fromOffset(20, prop_h - 2),
        Text = "▼",
        TextColor3 = theme.Text,
        TextSize = 12,
        Font = Enum.Font.SourceSansBold,
        Visible = false,
        ZIndex = 5,
    }, row)
    uifactory.Stroke(dropbutton, theme.BorderSoft)

    local categorybutton = uifactory.Create("TextButton", {
        Name = "CategoryButton",
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(propertycontroller.GetCanvasWidth(), prop_h),
        Text = "",
        Visible = false,
        ZIndex = 8,
    }, row)

    local bottom = uifactory.Create("Frame", {
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.fromOffset(propertycontroller.GetCanvasWidth(), 1),
        BackgroundColor3 = theme.BorderSoft,
        BorderSizePixel = 0,
    }, row)

    proprows[i] = {
        Root = row,
        Name = name,
        Value = value,
        ExpandButton = expandbutton,
        BoolBox = boolbox,
        ColorSwatch = colorswatch,
        RefButton = refbutton,
        DropButton = dropbutton,
        CategoryButton = categorybutton,
        Sep = sep,
        Bottom = bottom
    }

    categorybutton.MouseEnter:Connect(function()
        if categorybutton.Visible then
            row.BackgroundColor3 = theme.Hover
        end
    end)

    categorybutton.MouseLeave:Connect(function()
        if categorybutton.Visible then
            row.BackgroundColor3 = theme.Panel2
        end
    end)

    categorybutton.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]

        if p and p.Special == "Action" then
            if p.OnClick then
                p.OnClick(row)
            end

            return
        end

        if not p or p.Special ~= "Category" then
            return
        end

        local category = tostring(p.Category or p.Name or "Other")

        toolactions.PropertyCategoryCollapsed[category] =
            not toolactions.PropertyCategoryCollapsed[category]

        if toolactions.RebuildProperties then
            toolactions.RebuildProperties()
        end

        if toolactions.RenderProperties then
            toolactions.RenderProperties()
        end
    end)

    expandbutton.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]

        if not p or p.Special == "Category" or p.Special == "Component" then
            return
        end

        local key = toolactions.PropertyKey(p)

        toolactions.PropertyExpanded[key] =
            not toolactions.PropertyExpanded[key]

        if toolactions.RebuildProperties then
            toolactions.RebuildProperties()
        end
        if toolactions.RenderProperties then
            toolactions.RenderProperties()
        end
    end)

    refbutton.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]
        local valuenow, readable = toolactions.ReadEntryValue(p)

        if p and p.Special == "Tag" then
            local obj = selectednode and selectednode.obj

            if typeof(obj) == "Instance" then
                pcall(obj.RemoveTag, obj, p.TagName)
                propertycontroller.Rebuild()
                propertycontroller.Render()
            end

            return
        end

        if readable
            and typeof(valuenow) == "Instance"
            and toolactions.JumpToInstance
        then
            toolactions.JumpToInstance(valuenow)
        end
    end)

    colorswatch.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]
        local currentvalue, readable = toolactions.ReadEntryValue(p)

        if not readable or not p or p.ReadOnly then
            return
        end

        if typeof(currentvalue) == "Color3" then
            toolactions.OpenColorPicker(row, p, currentvalue)
        elseif typeof(currentvalue) == "BrickColor" then
            toolactions.OpenBrickPalette(row, p, currentvalue)
        end
    end)

    dropbutton.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]
        local currentvalue, readable = toolactions.ReadEntryValue(p)

        if not readable or not p or p.ReadOnly then
            return
        end

        local valuetype = typeof(currentvalue)

        if valuetype == "NumberSequence" or valuetype == "ColorSequence" then
            toolactions.OpenSequenceEditor(row, p, currentvalue)
        elseif valuetype == "BrickColor" then
            toolactions.OpenBrickPalette(row, p, currentvalue)
        else
            propertycontroller.OpenDropdown(row, p, currentvalue)
        end
    end)

    value.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return
        end

        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]
        local currentvalue, readable = toolactions.ReadEntryValue(p)

        if not readable or not p then
            return
        end

        local valuetype = typeof(currentvalue)

        if valuetype == "Instance" then
            if currentvalue and toolactions.JumpToInstance then
                toolactions.JumpToInstance(currentvalue)
            end
            return
        end

        if p.ReadOnly then
            return
        end

        if valuetype == "Color3" then
            toolactions.OpenColorPicker(row, p, currentvalue)
        elseif valuetype == "BrickColor" then
            toolactions.OpenBrickPalette(row, p, currentvalue)
        elseif valuetype == "NumberSequence" or valuetype == "ColorSequence" then
            toolactions.OpenSequenceEditor(row, p, currentvalue)
        elseif valuetype == "EnumItem" then
            propertycontroller.OpenDropdown(row, p, currentvalue)
        end
    end)

    row.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
            return
        end

        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]

        if p and p.Special ~= "Category" then
            toolactions.OpenPropertyMenu(row, p, input.Position)
        end
    end)

    boolbox.MouseEnter:Connect(function()
        if boolbox.Visible then
            local current = boolbox.Text == "✓"

            boolbox.BackgroundColor3 =
                current
                and Color3.fromRGB(255, 255, 255)
                or Color3.fromRGB(48, 51, 56)
        end
    end)

    boolbox.MouseLeave:Connect(function()
        if boolbox.Visible then
            local current = boolbox.Text == "✓"

            boolbox.BackgroundColor3 =
                current
                and Color3.fromRGB(238, 238, 238)
                or Color3.fromRGB(35, 37, 41)
        end
    end)

    boolbox.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]
        local old, readable = toolactions.ReadEntryValue(p)

        if not p
            or not readable
            or typeof(old) ~= "boolean"
            or p.ReadOnly
        then
            return
        end

        toolactions.WriteEntryValue(p, not old)
    end)

    value.FocusLost:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]

        if not p
            or p.Special == "Category"
            or p.ReadOnly
        then
            return
        end

        local old, readable = toolactions.ReadEntryValue(p)

        if not readable then
            return
        end

        local typename = p.ValueType

        if p.Special == "Component" then
            local oldtype = typeof(old)

            if oldtype == "number" then
                typename = "number"
            elseif oldtype == "string" then
                typename = "string"
            elseif oldtype == "boolean" then
                typename = "bool"
            else
                typename = oldtype
            end
        end

        local newvalue, ok =
            valuecodec.Parse(value.Text, typename, old)

        if not ok then
            value.Text = valuecodec.ToString(old)
            return
        end

        if not toolactions.WriteEntryValue(p, newvalue) then
            value.Text = valuecodec.ToString(old)
        end
    end)

end

for i = 1, prop_pool do propertycontroller.CreateRow(i) end

function propertycontroller.UpdateRowWidths()
    local width = propertycontroller.GetCanvasWidth()
    local visibleright = propertycontroller.GetVisibleRight()

    for _, r in proprows do
        r.Root.Size = UDim2.fromOffset(width, prop_h)

        r.ExpandButton.Position = UDim2.fromOffset(2, 0)
        r.ExpandButton.Size = UDim2.fromOffset(18, prop_h)

        r.Name.Position = UDim2.fromOffset(5, 0)
        r.Name.Size = UDim2.fromOffset(prop_name_w - 10, prop_h)

        r.Sep.Position = UDim2.fromOffset(prop_name_w, 0)

        r.Value.Position = UDim2.fromOffset(prop_name_w + 4, 1)
        r.Value.Size = UDim2.fromOffset(
            math.max(90, visibleright - prop_name_w - 33),
            prop_h - 2
        )

        r.BoolBox.Position = UDim2.fromOffset(
            prop_name_w + 8,
            math.floor((prop_h - 17) / 2)
        )

        r.ColorSwatch.Position = UDim2.fromOffset(
            prop_name_w + 8,
            math.floor((prop_h - 16) / 2)
        )

        r.RefButton.Position = UDim2.fromOffset(visibleright - 24, 1)
        r.RefButton.Size = UDim2.fromOffset(20, prop_h - 2)

        r.DropButton.Position = UDim2.fromOffset(visibleright - 24, 1)
        r.DropButton.Size = UDim2.fromOffset(20, prop_h - 2)

        r.CategoryButton.Size = UDim2.fromOffset(width, prop_h)
        r.Bottom.Size = UDim2.fromOffset(width, 1)
    end

    propscroll.CanvasSize = UDim2.fromOffset(
        width,
        #propertylist * prop_h
    )
end

propscroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
    propertycontroller.UpdateRowWidths()

    if toolactions.RenderProperties then
        toolactions.RenderProperties()
    end
end)

function propertycontroller.Rebuild()
    table.clear(propertylist)

    if not selectednode or not selectednode.obj then
        propscroll.CanvasSize = UDim2.fromOffset(propertycontroller.GetCanvasWidth(), 0)

        for _, r in proprows do
            r.Root.Visible = false
        end

        return
    end

    local obj = selectednode.obj

    local q = propsearch.Text:lower()
    local metadataprops = metadata:GetProperties(obj.ClassName)
    local runtimeprops = {}

    if metadataprops then
        for _, meta in metadataprops do
            local p = toolactions.RuntimePropertyEntry(obj, meta)

            if p then
                local category = tostring(p.Category or "Other")
                local matches =
                    q == ""
                    or p.Name:lower():find(q, 1, true)
                    or category:lower():find(q, 1, true)

                if matches then
                    runtimeprops[#runtimeprops + 1] = p
                end
            end
        end
    else

        local fallback = {
            {
                Name = "Name",
                Category = "Data",
                ValueType = "string",
                ReadOnly = false,
            },
            {
                Name = "Parent",
                Category = "Data",
                ValueType = "Instance",
                ReadOnly = false,
            },
            {
                Name = "ClassName",
                Category = "Data",
                ValueType = "string",
                ReadOnly = true,
            },
        }

        for _, p in fallback do
            local _, readable = valuecodec.ReadProperty(obj, p.Name)

            if readable
                and (
                    q == ""
                    or p.Name:lower():find(q, 1, true)
                    or p.Category:lower():find(q, 1, true)
                )
            then
                runtimeprops[#runtimeprops + 1] = p
            end
        end
    end

    local lastcategory = nil

    for _, p in runtimeprops do
        local category = p.Category or "Other"

        if category ~= lastcategory then
            lastcategory = category

            local collapsed =
                q == ""
                and toolactions.PropertyCategoryCollapsed[category] == true

            propertylist[#propertylist + 1] = {
                Name = category,
                Category = category,
                ValueType = "",
                Special = "Category",
                Collapsed = collapsed,
            }
        end

        local collapsed =
            q == ""
            and toolactions.PropertyCategoryCollapsed[category] == true

        if not collapsed then
            propertylist[#propertylist + 1] = p

            local currentvalue, readable =
                toolactions.ReadBasePropertyValue(p)

            if q == ""
                and readable
                and toolactions.IsExpandableValue(currentvalue)
                and toolactions.PropertyExpanded[
                    toolactions.PropertyKey(p)
                ]
            then
                for _, spec in toolactions.GetComponentSpecs(currentvalue) do
                    propertylist[#propertylist + 1] = {
                        Name = spec.Name,
                        Category = category,
                        ValueType = typeof(spec.Value),
                        Special = "Component",
                        ComponentKey = spec.Key,
                        ParentProp = p,
                        ReadOnly = p.ReadOnly,
                    }
                end
            end
        end
    end

    local attrs = obj:GetAttributes()
    local attrnames = {}

    for name in attrs do
        if q == ""
            or name:lower():find(q, 1, true)
            or ("attributes"):find(q, 1, true)
        then
            attrnames[#attrnames + 1] = name
        end
    end

    table.sort(attrnames, function(a, b)
        return a:lower() < b:lower()
    end)

    if #attrnames > 0 or q == "" then
        local attrscollapsed =
            q == ""
            and toolactions.PropertyCategoryCollapsed.Attributes == true

        propertylist[#propertylist + 1] = {
            Name = "Attributes",
            Category = "Attributes",
            ValueType = "",
            Special = "Category",
            Collapsed = attrscollapsed,
        }

        if not attrscollapsed then
            for _, name in attrnames do
                local attrprop = {
                    Name = name,
                    Category = "Attributes",
                    ValueType = typeof(attrs[name]),
                    Special = "Attribute",
                    AttrName = name,
                    ReadOnly = false,
                }

                propertylist[#propertylist + 1] = attrprop

                local attrvalue = attrs[name]

                if q == ""
                    and toolactions.IsExpandableValue(attrvalue)
                    and toolactions.PropertyExpanded[
                        toolactions.PropertyKey(attrprop)
                    ]
                then
                    for _, spec in toolactions.GetComponentSpecs(attrvalue) do
                        propertylist[#propertylist + 1] = {
                            Name = spec.Name,
                            Category = "Attributes",
                            ValueType = typeof(spec.Value),
                            Special = "Component",
                            ComponentKey = spec.Key,
                            ParentProp = attrprop,
                            ReadOnly = false,
                        }
                    end
                end
            end

            if q == "" then
                propertylist[#propertylist + 1] = {
                    Name = "Add Attribute",
                    Text = "+ Add Attribute",
                    Category = "Attributes",
                    ValueType = "",
                    Special = "Action",
                    OnClick = function(row)
                        toolactions.OpenAddDialog("Attribute", row)
                    end,
                }
            end
        end
    end

    local tagnames = {}
    local okt, tags = pcall(obj.GetTags, obj)

    if okt and type(tags) == "table" then
        for _, tag in tags do
            if q == ""
                or tag:lower():find(q, 1, true)
                or ("tags"):find(q, 1, true)
            then
                tagnames[#tagnames + 1] = tag
            end
        end
    end

    table.sort(tagnames, function(a, b)
        return a:lower() < b:lower()
    end)

    if #tagnames > 0 or q == "" then
        local tagscollapsed =
            q == ""
            and toolactions.PropertyCategoryCollapsed.Tags == true

        propertylist[#propertylist + 1] = {
            Name = "Tags",
            Category = "Tags",
            ValueType = "",
            Special = "Category",
            Collapsed = tagscollapsed,
        }

        if not tagscollapsed then
            for _, tag in tagnames do
                propertylist[#propertylist + 1] = {
                    Name = "Tag",
                    Category = "Tags",
                    ValueType = "string",
                    Special = "Tag",
                    TagName = tag,
                    ReadOnly = true,
                }
            end

            if q == "" then
                propertylist[#propertylist + 1] = {
                    Name = "Add Tag",
                    Text = "+ Add Tag",
                    Category = "Tags",
                    ValueType = "",
                    Special = "Action",
                    OnClick = function(row)
                        toolactions.OpenAddDialog("Tag", row)
                    end,
                }
            end
        end
    end

    propertycontroller.UpdateRowWidths()
end

function propertycontroller.Render()
    local start =
        math.max(
            1,
            math.floor(
                propscroll.CanvasPosition.Y / prop_h
            ) + 1
        )

    for i, r in proprows do
        local idx = start + i - 1
        local p = propertylist[idx]

        if p and selectednode and selectednode.obj then
            r.Root.Visible = true
            r.Root.Position =
                UDim2.fromOffset(
                    0,
                    (idx - 1) * prop_h
                )

            r.Root:SetAttribute("PropIndex", idx)

            if p.Special == "Category" or p.Special == "Action" then
                local isaction = p.Special == "Action"

                r.Root.BackgroundColor3 = isaction and theme.Panel or theme.Panel2
                r.Name.Position = UDim2.fromOffset(isaction and 24 or 5, 0)
                r.Name.Size =
                    UDim2.fromOffset(
                        propertycontroller.GetCanvasWidth() - 10,
                        prop_h
                    )

                r.Name.Text =
                    isaction
                    and p.Text
                    or ((p.Collapsed and "▶ " or "▼ ") .. p.Name)

                r.Name.TextColor3 = isaction and theme.Accent or theme.Accent2
                r.Value.Visible = false
                r.ExpandButton.Visible = false
                r.BoolBox.Visible = false
                r.ColorSwatch.Visible = false
                r.RefButton.Visible = false
                r.DropButton.Visible = false
                r.CategoryButton.Visible = true
                r.Sep.Visible = false
                r.Bottom.BackgroundColor3 = isaction and theme.BorderSoft or theme.Border
            else
                r.Root.BackgroundColor3 = theme.Panel
                r.CategoryButton.Visible = false
                r.Sep.Visible = true
                r.Bottom.BackgroundColor3 = theme.BorderSoft

                local v, readable =
                    toolactions.ReadEntryValue(p)

                local valuetype =
                    readable and typeof(v) or nil

                local isbool = valuetype == "boolean"
                local iscolor3 = valuetype == "Color3"
                local isbrickcolor = valuetype == "BrickColor"
                local isenumitem = valuetype == "EnumItem"
                local isinstance = valuetype == "Instance"
                local istag = p.Special == "Tag"
                local issequence =
                    valuetype == "NumberSequence"
                    or valuetype == "ColorSequence"

                local expandable =
                    p.Special ~= "Component"
                    and readable
                    and toolactions.IsExpandableValue(v)

                r.ExpandButton.Visible = expandable

                if expandable then
                    local expanded =
                        toolactions.PropertyExpanded[
                            toolactions.PropertyKey(p)
                        ] == true

                    r.ExpandButton.Text =
                        expanded and "▼" or "▶"

                    r.Name.Position =
                        UDim2.fromOffset(22, 0)

                    r.Name.Size =
                        UDim2.fromOffset(
                            prop_name_w - 27,
                            prop_h
                        )
                else
                    r.Name.Position =
                        UDim2.fromOffset(
                            p.Special == "Component"
                            and 28
                            or 5,
                            0
                        )

                    r.Name.Size =
                        UDim2.fromOffset(
                            prop_name_w
                            - (
                                p.Special == "Component"
                                and 33
                                or 10
                            ),
                            prop_h
                        )
                end

                r.Name.Text = p.Name

                if p.Special == "Attribute" then
                    r.Name.TextColor3 = theme.Accent
                elseif p.Special == "Component" then
                    r.Name.TextColor3 = theme.Dim
                else
                    r.Name.TextColor3 = theme.Text
                end

                r.BoolBox.Visible =
                    readable and isbool

                r.BoolBox.Active =
                    readable
                    and isbool
                    and not p.ReadOnly

                r.ColorSwatch.Visible =
                    readable
                    and (iscolor3 or isbrickcolor)

                r.ColorSwatch.Active =
                    readable
                    and (iscolor3 or isbrickcolor)
                    and not p.ReadOnly

                r.RefButton.Visible =
                    readable
                    and (
                        (isinstance and v ~= nil)
                        or istag
                    )

                r.RefButton.Active =
                    r.RefButton.Visible

                local reftext = istag and "✕" or "↗"

                if r.RefButton.Text ~= reftext then
                    r.RefButton.Text = reftext
                end

                local hasdropdown =
                    isenumitem
                    or isbrickcolor
                    or issequence

                local droptext = issequence and "…" or "▼"

                if r.DropButton.Text ~= droptext then
                    r.DropButton.Text = droptext
                end

                r.DropButton.Visible =
                    readable
                    and hasdropdown
                    and not p.ReadOnly

                r.DropButton.Active =
                    r.DropButton.Visible

                if isbool then
                    local checktext =
                        v and "✓" or ""

                    if r.BoolBox.Text ~= checktext then
                        r.BoolBox.Text = checktext
                    end

                    if v then
                        r.BoolBox.BackgroundColor3 =
                            Color3.fromRGB(238, 238, 238)

                        r.BoolBox.TextColor3 =
                            Color3.fromRGB(25, 25, 25)
                    else
                        r.BoolBox.BackgroundColor3 =
                            Color3.fromRGB(35, 37, 41)

                        r.BoolBox.TextColor3 =
                            Color3.fromRGB(35, 37, 41)
                    end

                    r.Value.Visible = false
                else
                    r.Value.Visible = true

                    local visibleright =
                        propertycontroller.GetVisibleRight()

                    local rightreserve =
                        (r.DropButton.Visible or r.RefButton.Visible)
                        and 31
                        or 5

                    if iscolor3 then
                        r.ColorSwatch.BackgroundColor3 = v
                        r.Value.Position =
                            UDim2.fromOffset(
                                prop_name_w + 30,
                                1
                            )

                        r.Value.Size =
                            UDim2.fromOffset(
                                math.max(
                                    76,
                                    visibleright
                                    - prop_name_w
                                    - 35
                                    - rightreserve
                                ),
                                prop_h - 2
                            )
                    elseif isbrickcolor then
                        r.ColorSwatch.BackgroundColor3 = v.Color
                        r.Value.Position =
                            UDim2.fromOffset(
                                prop_name_w + 30,
                                1
                            )

                        r.Value.Size =
                            UDim2.fromOffset(
                                math.max(
                                    76,
                                    visibleright
                                    - prop_name_w
                                    - 35
                                    - rightreserve
                                ),
                                prop_h - 2
                            )
                    else
                        r.Value.Position =
                            UDim2.fromOffset(
                                prop_name_w + 4,
                                1
                            )

                        r.Value.Size =
                            UDim2.fromOffset(
                                math.max(
                                    76,
                                    visibleright
                                    - prop_name_w
                                    - rightreserve
                                    - 4
                                ),
                                prop_h - 2
                            )
                    end

                    if not r.Value:IsFocused() then
                        local nexttext =
                            readable
                            and valuecodec.ToString(v)
                            or "<unavailable>"

                        if r.Value.Text ~= nexttext then
                            r.Value.Text = nexttext
                        end
                    end

                    r.Value.TextEditable =
                        readable
                        and not p.ReadOnly
                        and not isinstance
                        and not isenumitem
                        and not isbrickcolor
                        and not iscolor3
                        and not toolactions.IsExpandableValue(v)
                end

                if not readable then
                    r.Value.TextColor3 = theme.Dim
                elseif isinstance and v ~= nil then
                    r.Value.TextColor3 = theme.Accent2
                elseif p.ReadOnly then
                    r.Value.TextColor3 =
                        Color3.fromRGB(145, 148, 154)
                else
                    r.Value.TextColor3 = theme.Text
                end
            end
        else
            r.Root.Visible = false
            r.ExpandButton.Visible = false
            r.BoolBox.Visible = false
            r.ColorSwatch.Visible = false
            r.RefButton.Visible = false
            r.DropButton.Visible = false
            r.CategoryButton.Visible = false
            r.Root:SetAttribute("PropIndex", nil)
        end
    end
end

function treecontroller.ApplyPrimary(node)
    propertycontroller.CloseDropdown()
    toolactions.CloseColorPicker()
    toolactions.ClosePropertyMenu()
    if toolactions.CloseSequenceEditor then toolactions.CloseSequenceEditor() end
    if toolactions.CloseBrickPalette then toolactions.CloseBrickPalette() end
    if toolactions.CloseAttributeDialog then toolactions.CloseAttributeDialog() end
    selectednode = node

    runtimeutil.Disconnect(propertychangedconn)
    propertychangedconn = nil

    if node and node.obj then
        local ok, conn = pcall(function()
            return node.obj.Changed:Connect(function()
                toolactions.PropertyRealtimeDirty = true
            end)
        end)
        if ok then propertychangedconn = conn end
    end

    toolactions.PropertyRealtimeDirty = true
    propertycontroller.Rebuild()
    propertycontroller.UpdateRowWidths()
    propertycontroller.Render()

    if toolactions.UpdateSelectionVisual then
        toolactions.UpdateSelectionVisual()
    end
end

function treecontroller.SelectNode(node)
    local sel = toolactions.Selection

    table.clear(sel.Set)
    table.clear(sel.List)

    if node then
        sel.Set[node] = true
        sel.List[1] = node
    end

    sel.Anchor = node
    treecontroller.ApplyPrimary(node)
end

function treecontroller.SelectNodes(nodes, primary)
    local sel = toolactions.Selection

    table.clear(sel.Set)
    table.clear(sel.List)

    for _, node in nodes do
        if not sel.Set[node] then
            sel.Set[node] = true
            sel.List[#sel.List + 1] = node
        end
    end

    primary = primary or sel.List[#sel.List]
    treecontroller.ApplyPrimary(primary)
end

function treecontroller.ToggleNode(node)
    local sel = toolactions.Selection

    if sel.Set[node] then
        sel.Set[node] = nil
        table.remove(sel.List, table.find(sel.List, node))

        if selectednode == node then
            treecontroller.ApplyPrimary(sel.List[#sel.List])
        end
    else
        sel.Set[node] = true
        sel.List[#sel.List + 1] = node
        sel.Anchor = node
        treecontroller.ApplyPrimary(node)
    end
end

function treecontroller.SelectRange(node)
    local sel = toolactions.Selection
    local from = sel.Anchor and table.find(visiblenodes, sel.Anchor)
    local to = table.find(visiblenodes, node)

    if not from or not to then
        treecontroller.SelectNode(node)
        return
    end

    local nodes = {}
    local step = from <= to and 1 or -1

    for i = from, to, step do
        nodes[#nodes + 1] = visiblenodes[i]
    end

    treecontroller.SelectNodes(nodes, node)
end

function treecontroller.SelectAllVisible()
    local nodes = {}

    for _, node in visiblenodes do
        if node.obj then
            nodes[#nodes + 1] = node
        end
    end

    if #nodes > 0 then
        treecontroller.SelectNodes(nodes, selectednode and toolactions.Selection.Set[selectednode] and selectednode or nodes[1])
    end
end

function treecontroller.RemoveFromSelection(node)
    local sel = toolactions.Selection

    if not sel.Set[node] then
        return
    end

    sel.Set[node] = nil
    table.remove(sel.List, table.find(sel.List, node))

    if sel.Anchor == node then
        sel.Anchor = sel.List[#sel.List]
    end

    if selectednode == node then
        treecontroller.ApplyPrimary(sel.List[#sel.List])
    end
end

function treecontroller.GetSelectedObjects()
    local sel = toolactions.Selection
    local objects = {}
    local seen = {}

    for _, node in sel.List do
        local obj = node.obj

        if typeof(obj) == "Instance" and obj ~= rawgame then
            seen[obj] = true
        end
    end

    for _, node in sel.List do
        local obj = node.obj

        if seen[obj] then
            local covered = false
            local parent = obj.Parent

            while parent do
                if seen[parent] then
                    covered = true
                    break
                end

                parent = parent.Parent
            end

            if not covered then
                objects[#objects + 1] = obj
            end
        end
    end

    return objects
end

propsearch:GetPropertyChangedSignal("Text"):Connect(function()
    propertycontroller.CloseDropdown()
    toolactions.CloseColorPicker()
    toolactions.ClosePropertyMenu()
    propertycontroller.Rebuild()
    propertycontroller.UpdateRowWidths()
    propertycontroller.Render()
end)

toolactions.RebuildProperties = propertycontroller.Rebuild
toolactions.RenderProperties = propertycontroller.Render

propscroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    propertycontroller.CloseDropdown()
    toolactions.CloseColorPicker()
    toolactions.ClosePropertyMenu()
    propertycontroller.UpdateRowWidths()
    propertycontroller.Render()
end)

toolactions.PropertyRealtimeAccumulator = 0
toolactions.PropertyRealtimeInterval = 1 / 30
toolactions.PropertyRealtimeDirty = true

uis.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end

    local mouse = uis:GetMouseLocation()

    if propertydropdown.Visible then
        local pos = propertydropdown.AbsolutePosition
        local size = propertydropdown.AbsoluteSize

        if mouse.X < pos.X
            or mouse.X > pos.X + size.X
            or mouse.Y < pos.Y
            or mouse.Y > pos.Y + size.Y
        then
            propertycontroller.CloseDropdown()
        end
    end

    if toolactions.ColorPicker.Frame.Visible then
        local pos = toolactions.ColorPicker.Frame.AbsolutePosition
        local size = toolactions.ColorPicker.Frame.AbsoluteSize

        if mouse.X < pos.X
            or mouse.X > pos.X + size.X
            or mouse.Y < pos.Y
            or mouse.Y > pos.Y + size.Y
        then
            toolactions.CloseColorPicker()
        end
    end

    if toolactions.PropertyMenu.Frame.Visible then
        local pos = toolactions.PropertyMenu.Frame.AbsolutePosition
        local size = toolactions.PropertyMenu.Frame.AbsoluteSize

        if mouse.X < pos.X
            or mouse.X > pos.X + size.X
            or mouse.Y < pos.Y
            or mouse.Y > pos.Y + size.Y
        then
            toolactions.ClosePropertyMenu()
        end
    end
end)

toolactions.PropertyRealtimeConnection = runservice.Heartbeat:Connect(function(dt)
    if not selectednode or not selectednode.obj then
        return
    end

    if not main.Visible then
        return
    end

    toolactions.PropertyRealtimeAccumulator += dt

    if toolactions.PropertyRealtimeAccumulator
        < toolactions.PropertyRealtimeInterval
    then
        return
    end

    toolactions.PropertyRealtimeAccumulator = 0

    propertycontroller.Render()
    toolactions.PropertyRealtimeDirty = false

end)

local contextmenu = uifactory.Create("Frame", {
    Name = "ContextMenu",
    Visible = false,
    Size = UDim2.fromOffset(205, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Color3.fromRGB(25, 26, 30),
    BorderSizePixel = 0,
    ZIndex = 200,
}, rootgui)
uifactory.Round(contextmenu, 3)
uifactory.Stroke(contextmenu, Color3.fromRGB(54, 56, 63))

local menulayout = uifactory.Create("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 0),
}, contextmenu)

local menupad = uifactory.Create("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
    PaddingLeft = UDim.new(0, 0),
    PaddingRight = UDim.new(0, 0),
}, contextmenu)

local submenu = uifactory.Create("Frame", {
    Name = "SubMenu",
    Visible = false,
    Size = UDim2.fromOffset(190, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundColor3 = Color3.fromRGB(25, 26, 30),
    BorderSizePixel = 0,
    ZIndex = 205,
}, rootgui)
uifactory.Round(submenu, 3)
uifactory.Stroke(submenu, Color3.fromRGB(54, 56, 63))

local submenulayout = uifactory.Create("UIListLayout", {
    SortOrder = Enum.SortOrder.LayoutOrder,
}, submenu)

local submenupad = uifactory.Create("UIPadding", {
    PaddingTop = UDim.new(0, 4),
    PaddingBottom = UDim.new(0, 4),
}, submenu)

local submenubridge = uifactory.Create("Frame", {
    Name = "SubMenuBridge",
    Visible = false,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(8, 25),
    ZIndex = 204,
}, rootgui)

local contextnode = nil
local currentsubmenuowner = nil

function menucontroller.Close()
    if currentsubmenuowner then
        currentsubmenuowner.BackgroundTransparency = 1
    end

    contextmenu.Visible = false
    submenu.Visible = false
    submenubridge.Visible = false
    currentsubmenuowner = nil
end

function menucontroller.MenuSeparator(parent)
    return uifactory.Create("Frame", {
        Size = UDim2.new(1, 0, 0, 7),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, parent)
end

function menucontroller.SeparatorLine(parent)
    local holder = menucontroller.MenuSeparator(parent)
    uifactory.Create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 9, 0.5, 0),
        Size = UDim2.new(1, -18, 0, 1),
        BackgroundColor3 = Color3.fromRGB(52, 54, 61),
        BorderSizePixel = 0,
        ZIndex = parent.ZIndex + 1,
    }, holder)
    return holder
end

function menucontroller.CreateItem(parent, textvalue, fn, options)
    options = options or {}

    local b = uifactory.Create("TextButton", {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 24),
        Text = "",
        ZIndex = parent.ZIndex + 1,
    }, parent)

    local label = uifactory.Text(b, textvalue, 16)
    label.Position = UDim2.fromOffset(12, 0)
    label.Size = UDim2.new(1, options.submenu and -34 or -20, 1, 0)
    label.ZIndex = b.ZIndex + 1
    label.TextColor3 = options.disabled and Color3.fromRGB(105, 107, 112) or theme.Text

    local arrow = nil
    if options.submenu then
        arrow = uifactory.Text(b, "›", 15, Enum.TextXAlignment.Center)
        arrow.Position = UDim2.new(1, -24, 0, 0)
        arrow.Size = UDim2.fromOffset(20, 25)
        arrow.ZIndex = b.ZIndex + 1
        arrow.TextColor3 = theme.Dim
    end

    local function showhover()
        if options.disabled then return end
        b.BackgroundTransparency = 0
        b.BackgroundColor3 = Color3.fromRGB(47, 76, 111)
    end

    local function hidehover()

        if currentsubmenuowner == b and submenu.Visible then
            return
        end
        b.BackgroundTransparency = 1
    end

    b.MouseEnter:Connect(function()
        showhover()

        if options.submenu and options.buildSubmenu then
            if currentsubmenuowner and currentsubmenuowner ~= b then
                currentsubmenuowner.BackgroundTransparency = 1
            end

            currentsubmenuowner = b

            for _, child in submenu:GetChildren() do
                if child ~= submenulayout and child ~= submenupad and not child:IsA("UICorner") and not child:IsA("UIStroke") then
                    child:Destroy()
                end
            end

            options.buildSubmenu(submenu)

            local ap = b.AbsolutePosition
            local as = b.AbsoluteSize
            local screen = rootgui.AbsoluteSize

            local x = ap.X + as.X - 2
            local y = ap.Y - 4

            task.defer(function()
                local subsize = submenu.AbsoluteSize
                if x + subsize.X > screen.X then
                    x = ap.X - subsize.X + 2
                end
                if y + subsize.Y > screen.Y then
                    y = math.max(0, screen.Y - subsize.Y)
                end

                submenu.Position = UDim2.fromOffset(x, y)
                submenu.Visible = true

                local ownerright = ap.X + as.X
                local subleft = x

                if subleft >= ownerright then
                    submenubridge.Position = UDim2.fromOffset(ownerright - 2, ap.Y)
                    submenubridge.Size = UDim2.fromOffset(
                        math.max(6, subleft - ownerright + 4),
                        as.Y
                    )
                else
                    local subright = x + submenu.AbsoluteSize.X
                    submenubridge.Position = UDim2.fromOffset(subright - 2, ap.Y)
                    submenubridge.Size = UDim2.fromOffset(
                        math.max(6, ap.X - subright + 4),
                        as.Y
                    )
                end

                submenubridge.Visible = true
            end)
        elseif not options.submenu then

            if parent ~= submenu then
                if currentsubmenuowner then
                    currentsubmenuowner.BackgroundTransparency = 1
                end

                submenu.Visible = false
                submenubridge.Visible = false
                currentsubmenuowner = nil
            end
        end
    end)

    b.MouseLeave:Connect(hidehover)

    if not options.disabled and not options.submenu and fn then
        b.MouseButton1Click:Connect(function()
            menucontroller.Close()
            if contextnode then
                fn(contextnode)
            end
        end)
    end

    return b
end

function menucontroller.IsScript(obj: Instance): boolean
    return obj
        and (
            obj:IsA("Script")
            or obj:IsA("LocalScript")
            or obj:IsA("ModuleScript")
        )
end

function menucontroller.CopyText(textvalue)
    adapter:Copy(tostring(textvalue or ""))
end

function menucontroller.CopyObjectPath(obj)
    if obj then
        menucontroller.CopyText(treecontroller.GetPath(obj))
    end
end

function menucontroller.RefreshParents(objects)
    local done = {}

    for _, obj in objects do
        local parentnode = obj.Parent and nodesbyobject[obj.Parent]

        if parentnode and parentnode.loaded and not done[parentnode] then
            done[parentnode] = true
            parentnode.loaded = false
            treecontroller.LoadChildren(parentnode)
        end
    end

    treecontroller.BuildVisible()
    treecontroller.Render(true)
end

function menucontroller.CloneObject(obj)
    local oldarchivable = obj.Archivable
    local clone

    pcall(function()
        obj.Archivable = true
        clone = obj:Clone()
        obj.Archivable = oldarchivable
    end)

    return clone
end

function menucontroller.DuplicateObjects(objects)
    local clones = {}

    for _, obj in objects do
        local clone = menucontroller.CloneObject(obj)

        if clone and pcall(function() clone.Parent = obj.Parent end) then
            clones[#clones + 1] = clone
        end
    end

    if #clones > 0 then
        menucontroller.RefreshParents(clones)
        statuslabel.Text = ("Duplicated %d"):format(#clones)
    end
end

local cutbuffer = nil
local copybuffer = nil

function menucontroller.CutObjects(objects)
    if #objects == 0 then return end

    cutbuffer = {Objects = objects}
    copybuffer = nil

    for _, obj in objects do
        pcall(function()
            obj.Parent = nil
        end)
    end

    statuslabel.Text = ("Cut %d • Ctrl+V to paste"):format(#objects)
end

function menucontroller.CopyObjects(objects)
    local clones = {}

    for _, obj in objects do
        local clone = menucontroller.CloneObject(obj)

        if clone then
            clones[#clones + 1] = clone
        end
    end

    if #clones > 0 then
        copybuffer = {Objects = clones}
        cutbuffer = nil
        statuslabel.Text = ("Copied %d"):format(#clones)
    end
end

function menucontroller.HasClipboard()
    return (cutbuffer ~= nil and #cutbuffer.Objects > 0)
        or (copybuffer ~= nil and #copybuffer.Objects > 0)
end

function menucontroller.PasteInto(target)
    if not target then return end

    local pasted = {}

    if cutbuffer then
        for _, obj in cutbuffer.Objects do
            if pcall(function() obj.Parent = target end) then
                pasted[#pasted + 1] = obj
            end
        end

        cutbuffer = nil
    elseif copybuffer then
        for _, source in copybuffer.Objects do
            local clone

            if pcall(function()
                clone = source:Clone()
                clone.Parent = target
            end) and clone then
                pasted[#pasted + 1] = clone
            end
        end
    end

    if #pasted > 0 then
        statuslabel.Text = ("Pasted %d"):format(#pasted)
        menucontroller.RefreshParents(pasted)
    end
end

function menucontroller.PasteIntoSelection()
    local targets = {}

    for _, node in toolactions.Selection.List do
        if typeof(node.obj) == "Instance" then
            targets[#targets + 1] = node.obj
        end
    end

    for _, target in targets do
        menucontroller.PasteInto(target)

        if not menucontroller.HasClipboard() then
            break
        end
    end
end

function menucontroller.DeleteObjects(objects)
    for _, obj in objects do
        pcall(function()
            obj:Destroy()
        end)
    end

    if #objects > 0 then
        statuslabel.Text = ("Deleted %d"):format(#objects)
    end
end

function menucontroller.RenameObject(node)
    if not node.obj then return end

    local box = uifactory.Create("TextBox", {
        Size = UDim2.fromOffset(280, 34),
        Position = UDim2.new(0.5, -140, 0.5, -17),
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        Text = node.obj.Name,
        TextColor3 = theme.Text,
        TextSize = 14,
        Font = Enum.Font.SourceSans,
        FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal),
        ClearTextOnFocus = false,
        ZIndex = 300,
    }, rootgui)
    uifactory.Round(box, 5)
    uifactory.Stroke(box, theme.Accent)

    box:CaptureFocus()
    box.SelectionStart = 1
    box.CursorPosition = #box.Text + 1

    box.FocusLost:Connect(function(enter)
        if enter and node.obj then
            pcall(function()
                node.obj.Name = box.Text
            end)
        end
        box:Destroy()
        treecontroller.BuildVisible()
        treecontroller.Render()
    end)
end

function treecontroller.ExpandAncestors(node)
    if not node then return end

    local chain = {}
    local cur = node

    while cur and cur ~= root do
        table.insert(chain, 1, cur)
        cur = cur.parent
    end

    local parent = root
    parent.expanded = true
    treecontroller.LoadChildren(parent)

    for _, childnode in chain do
        if parent and parent ~= childnode then
            treecontroller.LoadChildren(parent)

            local matched = nil
            for _, c in parent.children do
                if c.obj == childnode.obj then
                    matched = c
                    break
                end
            end

            if matched then
                matched.parent = parent
                matched.depth = parent.depth + 1
                parent.expanded = true
                parent = matched
            end
        end
    end

    if parent then
        parent.expanded = true
    end
end

function treecontroller.ScrollIntoView(node)
    treecontroller.BuildVisible()

    local idx = table.find(visiblenodes, node)

    if not idx and node and node.obj then
        for i, n in visiblenodes do
            if n.obj == node.obj then
                idx = i
                node = n
                break
            end
        end
    end

    if idx then
        local viewh = treescroll.AbsoluteSize.Y
        local y = (idx - 1) * row_h
        local desired = math.max(0, y - math.floor(viewh * 0.35))

        treescroll.CanvasPosition = Vector2.new(
            treescroll.CanvasPosition.X,
            desired
        )

        selectednode = node
        treecontroller.SelectNode(node)
        treecontroller.Render()
    end
end

function treecontroller.JumpToNode(node)
    if not node or not node.obj then return end

    local objects = {}
    local curobj = node.obj

    while curobj and curobj ~= rawgame do
        table.insert(objects, 1, curobj)
        curobj = curobj.Parent
    end

    local parentnode = root
    parentnode.expanded = true
    treecontroller.LoadChildren(parentnode)

    local targetnode = nil

    for _, obj in objects do
        treecontroller.LoadChildren(parentnode)

        local nextnode = nil

        for _, child in parentnode.children do
            if child.obj == obj then
                nextnode = child
                break
            end
        end

        if not nextnode then
            nextnode = treecontroller.GetOrCreateNode(obj, parentnode)
            parentnode.children[#parentnode.children + 1] = nextnode
            table.sort(parentnode.children, treecontroller.CompareNodes)
        end

        parentnode.expanded = true
        nextnode.parent = parentnode
        nextnode.depth = parentnode.depth + 1

        targetnode = nextnode
        parentnode = nextnode
    end

    if targetnode then
        searchmode = false
        search.Text = ""
        treecontroller.ScrollIntoView(targetnode)
        statuslabel.Text = "Jumped to " .. targetnode.obj:GetFullName()
    end
end

toolactions.JumpToInstance = function(obj)
    if typeof(obj) ~= "Instance" then
        return
    end

    local node = nodesbyobject[obj]

    if not node then
        node = treecontroller.GetOrCreateNode(obj, nil)
    end

    treecontroller.JumpToNode(node)
end

function viewercontroller.OpenNodeScript(node)
    if node.obj and menucontroller.IsScript(node.obj) then
        toolactions.OpenScriptViewer(node.obj)
    else
        statuslabel.Text = "Selected object is not a script"
    end
end

function menucontroller.BuildCopyAsMenu(parent)
    menucontroller.CreateItem(parent, "Path", function(node)
        menucontroller.CopyObjectPath(node.obj)
    end)

    menucontroller.CreateItem(parent, "Full Name", function(node)
        if node.obj then
            menucontroller.CopyText(node.obj:GetFullName())
        end
    end)

    menucontroller.CreateItem(parent, "Name", function(node)
        if node.obj then
            menucontroller.CopyText(node.obj.Name)
        end
    end)

    menucontroller.CreateItem(parent, "ClassName", function(node)
        if node.obj then
            menucontroller.CopyText(node.obj.ClassName)
        end
    end)

    menucontroller.SeparatorLine(parent)

    menucontroller.CreateItem(parent, "CFrame", function(node)
        local obj = node.obj
        if not obj then return end

        local ok, cf = pcall(function()
            if obj:IsA("BasePart") then
                return obj.CFrame
            elseif obj:IsA("Model") then
                return obj:GetPivot()
            end
        end)

        if ok and cf then
            menucontroller.CopyText(tostring(cf))
        end
    end, {
        disabled = not (
            contextnode
            and contextnode.obj
            and (
                contextnode.obj:IsA("BasePart")
                or contextnode.obj:IsA("Model")
            )
        )
    })
end

function menucontroller.BuildHierarchyMenu(parent)
    menucontroller.CreateItem(parent, "Jump To Parent", function(node)
        if node.parent and node.parent ~= root then
            treecontroller.JumpToNode(node.parent)
        elseif node.obj and node.obj.Parent and node.obj.Parent ~= rawgame then
            local p = nodesbyobject[node.obj.Parent] or treecontroller.GetOrCreateNode(node.obj.Parent, nil)
            treecontroller.JumpToNode(p)
        end
    end, {
        disabled = not (
            contextnode
            and contextnode.obj
            and contextnode.obj.Parent
            and contextnode.obj.Parent ~= rawgame
        )
    })

    menucontroller.CreateItem(parent, "Expand Children", function(node)
        if not node then return end

        local stack = {node}
        local processed = 0
        local max_expand = 15000

        local slicestart = os.clock()
        local slice_seconds = 0.006

        while #stack > 0 and processed < max_expand do
            local current = table.remove(stack)

            if current then
                if current.pseudo then
                    if current == nilroot then
                        treecontroller.LoadNilChildren()
                    end
                elseif current.obj then
                    treecontroller.LoadChildren(current)
                end

                current.expanded = true
                processed += 1

                local children = current.children or {}
                for i = #children, 1, -1 do
                    stack[#stack + 1] = children[i]
                end

                if os.clock() - slicestart >= slice_seconds then
                    statuslabel.Text = ("Expanding... %d nodes"):format(processed)
                    task.wait()
                    slicestart = os.clock()
                end
            end
        end

        treecontroller.ScrollIntoView(node)

        if processed >= max_expand then
            statuslabel.Text = ("Expanded %d nodes (safety limit)"):format(processed)
        else
            statuslabel.Text = ("Expanded %d nodes"):format(processed)
        end
    end)

    menucontroller.CreateItem(parent, "Collapse Children", function(node)
        if not node then return end

        local stack = {node}
        local processed = 0
        local slicestart = os.clock()
        local slice_seconds = 0.006

        while #stack > 0 do
            local current = table.remove(stack)

            if current then
                current.expanded = false
                processed += 1

                local children = current.children or {}
                for i = #children, 1, -1 do
                    stack[#stack + 1] = children[i]
                end

                if os.clock() - slicestart >= slice_seconds then
                    task.wait()
                    slicestart = os.clock()
                end
            end
        end

        treecontroller.ScrollIntoView(node)
        statuslabel.Text = ("Collapsed %d nodes"):format(processed)
    end)

    menucontroller.SeparatorLine(parent)

    menucontroller.CreateItem(parent, "Paste Into", function(node)
        if node.obj then
            menucontroller.PasteInto(node.obj)
        end
    end, {
        disabled = not menucontroller.HasClipboard()
    })
end

function menucontroller.Rebuild()
    for _, child in contextmenu:GetChildren() do
        if child ~= menulayout and child ~= menupad and not child:IsA("UICorner") and not child:IsA("UIStroke") then
            child:Destroy()
        end
    end

    if not contextnode then return end

    local obj = contextnode.obj

    local selected = treecontroller.GetSelectedObjects()
    local hasselection = #selected > 0

    menucontroller.CreateItem(contextmenu, "Cut", function()
        menucontroller.CutObjects(selected)
    end, {
        disabled = not hasselection
    })

    menucontroller.CreateItem(contextmenu, "Copy", function()
        menucontroller.CopyObjects(selected)
    end, {
        disabled = not hasselection
    })

    menucontroller.CreateItem(contextmenu, "Copy As", nil, {
        submenu = true,
        buildSubmenu = menucontroller.BuildCopyAsMenu,
    })

    menucontroller.SeparatorLine(contextmenu)

    menucontroller.CreateItem(contextmenu, "Duplicate", function()
        menucontroller.DuplicateObjects(selected)
    end, {
        disabled = not hasselection
    })

    menucontroller.CreateItem(contextmenu, "Delete", function()
        menucontroller.DeleteObjects(selected)
    end, {
        disabled = not hasselection
    })

    menucontroller.CreateItem(contextmenu, "Rename", menucontroller.RenameObject, {
        disabled = not obj or obj == rawgame
    })

    menucontroller.SeparatorLine(contextmenu)

    menucontroller.CreateItem(contextmenu, "Jump To Select", treecontroller.JumpToNode)

    menucontroller.CreateItem(contextmenu, "View Script", viewercontroller.OpenNodeScript, {
        disabled = not menucontroller.IsScript(obj)
    })

    menucontroller.SeparatorLine(contextmenu)

    menucontroller.CreateItem(contextmenu, "Hierarchy", nil, {
        submenu = true,
        buildSubmenu = menucontroller.BuildHierarchyMenu,
    })

    if obj and obj:IsA("BasePart") then
        menucontroller.SeparatorLine(contextmenu)

        menucontroller.CreateItem(contextmenu, "Teleport To", function(node)
            local target = node.obj
            if not target or not target:IsA("BasePart") then
                return
            end

            local character = localplayer and localplayer.Character
            local primarypart = character and character.PrimaryPart

            if not primarypart then
                return
            end

            primarypart.CFrame = target.CFrame
        end)
    end

    local firetargets = {
        ClickDetector = {},
        ProximityPrompt = {},
        TouchTransmitter = {},
    }
    local hasfire = false

    for _, node in toolactions.Selection.List do
        local target = node.obj

        if typeof(target) == "Instance" then
            for classname, list in firetargets do
                if target:IsA(classname) then
                    list[#list + 1] = target
                    hasfire = true
                end
            end
        end
    end

    if hasfire then
        menucontroller.SeparatorLine(contextmenu)

        if #firetargets.ClickDetector > 0 then
            menucontroller.CreateItem(contextmenu, "Fire ClickDetector", function()
                for _, target in firetargets.ClickDetector do
                    pcall(adapter.fireclickdetector, target)
                end
            end, {
                disabled = adapter.fireclickdetector == nil
            })
        end

        if #firetargets.ProximityPrompt > 0 then
            menucontroller.CreateItem(contextmenu, "Fire ProximityPrompt", function()
                for _, target in firetargets.ProximityPrompt do
                    pcall(adapter.fireproximityprompt, target)
                end
            end, {
                disabled = adapter.fireproximityprompt == nil
            })
        end

        if #firetargets.TouchTransmitter > 0 then
            menucontroller.CreateItem(contextmenu, "Fire TouchTransmitter", function()
                local character = localplayer and localplayer.Character
                local root = character and (
                    character:FindFirstChild("HumanoidRootPart")
                    or character.PrimaryPart
                )

                if not root then
                    return
                end

                for _, target in firetargets.TouchTransmitter do
                    local part = target.Parent

                    if part and part:IsA("BasePart") then
                        pcall(adapter.firetouchinterest, root, part, 0)
                        task.wait()
                        pcall(adapter.firetouchinterest, root, part, 1)
                    end
                end
            end, {
                disabled = adapter.firetouchinterest == nil
            })
        end
    end
end

function menucontroller.Open(node, screenposition)
    contextnode = node

    if currentsubmenuowner then
        currentsubmenuowner.BackgroundTransparency = 1
    end

    submenu.Visible = false
    submenubridge.Visible = false
    currentsubmenuowner = nil

    menucontroller.Rebuild()

    local x = screenposition.X
    local y = screenposition.Y

    contextmenu.Position = UDim2.fromOffset(x, y)
    contextmenu.Visible = true

    task.defer(function()
        local size = contextmenu.AbsoluteSize
        local screen = rootgui.AbsoluteSize

        if x + size.X > screen.X then
            x = math.max(0, screen.X - size.X)
        end

        if y + size.Y > screen.Y then
            y = math.max(0, screen.Y - size.Y)
        end

        contextmenu.Position = UDim2.fromOffset(x, y)
    end)
end

uis.InputBegan:Connect(function(input)
    if not contextmenu.Visible and not submenu.Visible then
        return
    end

    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        local p = input.Position

        local function inside(gui)
            if not gui.Visible then return false end
            local ap = gui.AbsolutePosition
            local as = gui.AbsoluteSize
            return
                p.X >= ap.X
                and p.X <= ap.X + as.X
                and p.Y >= ap.Y
                and p.Y <= ap.Y + as.Y
        end

        if not inside(contextmenu) and not inside(submenu) and not inside(submenubridge) then
            menucontroller.Close()
        end
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then

        submenu.Visible = false
        submenubridge.Visible = false
    end
end)

toolactions.Shortcuts = {
    [Enum.KeyCode.C] = function()
        menucontroller.CopyObjects(treecontroller.GetSelectedObjects())
    end,
    [Enum.KeyCode.X] = function()
        menucontroller.CutObjects(treecontroller.GetSelectedObjects())
    end,
    [Enum.KeyCode.V] = function()
        menucontroller.PasteIntoSelection()
    end,
    [Enum.KeyCode.D] = function()
        menucontroller.DuplicateObjects(treecontroller.GetSelectedObjects())
    end,
    [Enum.KeyCode.A] = function()
        treecontroller.SelectAllVisible()
        treecontroller.Render()
    end,
}

uis.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end

    if not rootgui.Parent or not main.Visible or uis:GetFocusedTextBox() then
        return
    end

    if toolactions.ViewerUI.Overlay.Visible
        or (toolactions.Settings.Frame and toolactions.Settings.Frame.Visible)
        or (toolactions.CreditsFrame and toolactions.CreditsFrame.Visible)
        or not toolactions.PointInside(treescroll, uis:GetMouseLocation())
    then
        return
    end

    local ctrl = uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)

    if ctrl then
        local action = toolactions.Shortcuts[input.KeyCode]

        if action then
            action()
        end
    elseif input.KeyCode == Enum.KeyCode.Delete then
        menucontroller.DeleteObjects(treecontroller.GetSelectedObjects())
    end
end)

toolactions.Settings = {
    Path = "Explorer/settings.json",
    Values = {
        ClickPartToSelect = false,
        ClickUIToSelect = false,
    },
    Toggles = {},
}

toolactions.Settings.Load = function()
    local raw = cachestore.Read(toolactions.Settings.Path)

    if not raw then
        return
    end

    local ok, decoded = pcall(httpservice.JSONDecode, httpservice, raw)

    if not ok or type(decoded) ~= "table" then
        return
    end

    for key in toolactions.Settings.Values do
        if type(decoded[key]) == "boolean" then
            toolactions.Settings.Values[key] = decoded[key]
        end
    end

    if type(decoded.SaveOptions) == "table" then
        for name, value in decoded.SaveOptions do
            local def = toolactions.Settings.OptionDefs[name]

            if def then
                local expected =
                    def.Type == "bool" and "boolean"
                    or def.Type == "number" and "number"
                    or "string"

                if type(value) == expected then
                    toolactions.Settings.SaveOptions[name] = value
                end
            end
        end
    end
end

toolactions.Settings.Save = function()
    local payload = {
        SaveOptions = toolactions.Settings.SaveOptions or {},
    }

    for key, value in toolactions.Settings.Values do
        payload[key] = value
    end

    local ok, encoded = pcall(
        httpservice.JSONEncode,
        httpservice,
        payload
    )

    if ok then
        cachestore.Write(toolactions.Settings.Path, encoded)
    end
end

toolactions.Settings.Frame = uifactory.Create("Frame", {
    Name = "SettingsPage",
    Visible = false,
    BackgroundColor3 = theme.Panel,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 28),
    Size = UDim2.new(1, 0, 1, -28),
    Active = true,
    ZIndex = 60,
}, main)

do
    local header = uifactory.Create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = theme.Panel2,
        BorderSizePixel = 0,
        ZIndex = 61,
    }, toolactions.Settings.Frame)

    local title = uifactory.Text(header, "Settings", 16)
    title.Position = UDim2.fromOffset(8, 0)
    title.Size = UDim2.new(1, -16, 1, 0)
    title.ZIndex = 62
end

toolactions.Settings.Content = uifactory.Create("ScrollingFrame", {
    Name = "Content",
    Position = UDim2.fromOffset(0, 28),
    Size = UDim2.new(1, 0, 1, -28),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 7,
    ScrollBarImageColor3 = Color3.fromRGB(92, 92, 92),
    CanvasSize = UDim2.fromOffset(0, 290),
    ScrollingDirection = Enum.ScrollingDirection.Y,
    ElasticBehavior = Enum.ElasticBehavior.Never,
    ZIndex = 61,
}, toolactions.Settings.Frame)

toolactions.Settings.CreateSection = function(text, y)
    local label = uifactory.Text(toolactions.Settings.Content, text, 15)
    label.Position = UDim2.fromOffset(12, y)
    label.Size = UDim2.new(1, -24, 0, 18)
    label.TextColor3 = theme.Accent2
    label.ZIndex = 62

    uifactory.Create("Frame", {
        Position = UDim2.fromOffset(12, y + 20),
        Size = UDim2.new(1, -24, 0, 1),
        BackgroundColor3 = theme.BorderSoft,
        BorderSizePixel = 0,
        ZIndex = 62,
    }, toolactions.Settings.Content)
end

toolactions.Settings.RefreshToggle = function(key)
    local toggle = toolactions.Settings.Toggles[key]

    if not toggle then
        return
    end

    local enabled = toolactions.Settings.Values[key] == true

    toggle.Box.BackgroundColor3 =
        enabled
        and Color3.fromRGB(238, 238, 238)
        or Color3.fromRGB(35, 37, 41)

    toggle.Check.Text = enabled and "✓" or ""
end

toolactions.Settings.CreateToggle = function(key, labeltext, y)
    local row = uifactory.Create("TextButton", {
        Position = UDim2.fromOffset(6, y),
        Size = UDim2.new(1, -12, 0, 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 71,
    }, toolactions.Settings.Content)
    uifactory.Round(row, 4)

    local box = uifactory.Create("Frame", {
        Position = UDim2.fromOffset(8, 5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.fromRGB(35, 37, 41),
        BorderSizePixel = 0,
        ZIndex = 72,
    }, row)
    uifactory.Round(box, 1)
    uifactory.Stroke(box, Color3.fromRGB(105, 108, 114))

    local check = uifactory.Create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = Color3.fromRGB(25, 25, 25),
        TextSize = 16,
        Font = Enum.Font.SourceSansBold,
        ZIndex = 73,
    }, box)

    local label = uifactory.Text(row, labeltext, 16)
    label.Position = UDim2.fromOffset(34, 0)
    label.Size = UDim2.new(1, -40, 1, 0)
    label.ZIndex = 72

    row.MouseEnter:Connect(function()
        row.BackgroundTransparency = 0
        row.BackgroundColor3 = theme.Hover
    end)

    row.MouseLeave:Connect(function()
        row.BackgroundTransparency = 1
    end)

    row.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        toolactions.Settings.Values[key] = not toolactions.Settings.Values[key]
        toolactions.Settings.RefreshToggle(key)
        toolactions.Settings.Save()
    end)

    toolactions.Settings.Toggles[key] = {
        Row = row,
        Box = box,
        Check = check,
    }

    toolactions.Settings.RefreshToggle(key)
end

toolactions.Settings.CreateSection("General", 8)
toolactions.Settings.CreateToggle("ClickPartToSelect", "Click Part to Select", 34)
toolactions.Settings.CreateToggle("ClickUIToSelect", "Click UI to Select", 64)

toolactions.Settings.CreateSection("SaveInstance", 108)

toolactions.Settings.SaveButton = uifactory.Create("TextButton", {
    Position = UDim2.fromOffset(12, 136),
    Size = UDim2.new(1, -24, 0, 30),
    BackgroundColor3 = theme.Selected,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "Save Game",
    TextColor3 = theme.Text,
    TextSize = 16,
    Font = Enum.Font.SourceSans,
    ZIndex = 62,
}, toolactions.Settings.Content)
uifactory.Round(toolactions.Settings.SaveButton, 4)

toolactions.Settings.ResetButton =uifactory.Create("TextButton", {
    Position = UDim2.fromOffset(12, 216),
    Size = UDim2.new(1, -24, 0, 24),
    BackgroundColor3 = theme.Panel2,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "Reset All Options",
    TextColor3 = theme.Dim,
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    ZIndex = 62,
}, toolactions.Settings.Content)
uifactory.Round(toolactions.Settings.ResetButton, 4)

toolactions.Settings.SaveButton.MouseEnter:Connect(function()
    if not toolactions.Settings.SaveBusy then
        toolactions.Settings.SaveButton.BackgroundColor3 = Color3.fromRGB(58, 100, 135)
    end
end)

toolactions.Settings.SaveButton.MouseLeave:Connect(function()
    toolactions.Settings.SaveButton.BackgroundColor3 = theme.Selected
end)

toolactions.Settings.ResetButton.MouseEnter:Connect(function()
    toolactions.Settings.ResetButton.BackgroundColor3 = theme.Hover
end)

toolactions.Settings.ResetButton.MouseLeave:Connect(function()
    toolactions.Settings.ResetButton.BackgroundColor3 = theme.Panel2
end)

toolactions.Settings.SaveOptions = {}
toolactions.Settings.OptionRefreshers = {}
toolactions.Settings.OptionDefs = {}

toolactions.Settings.OptionGroups = {
    {"", {
        {Name = "noscripts", Type = "bool", Default = false},
    }},
}

toolactions.Settings.GetOption = function(def)
    local value = toolactions.Settings.SaveOptions[def.Name]

    if value == nil then
        return def.Default
    end

    return value
end

toolactions.Settings.SetOption = function(def, value)
    local options = toolactions.Settings.SaveOptions

    if value == nil or value == "" or value == def.Default then
        options[def.Name] = nil
    else
        options[def.Name] = value
    end

    toolactions.Settings.Save()

    for _, refresh in toolactions.Settings.OptionRefreshers do
        refresh()
    end
end

toolactions.Settings.CreateOptionToggle = function(def, y)
    local row = uifactory.Create("TextButton", {
        Position = UDim2.fromOffset(6, y),
        Size = UDim2.new(1, -12, 0, 28),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        ZIndex = 71,
    }, toolactions.Settings.Content)
    uifactory.Round(row, 4)

    local box = uifactory.Create("Frame", {
        Position = UDim2.fromOffset(8, 5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundColor3 = Color3.fromRGB(35, 37, 41),
        BorderSizePixel = 0,
        ZIndex = 72,
    }, row)
    uifactory.Round(box, 1)
    uifactory.Stroke(box, Color3.fromRGB(105, 108, 114))

    local check = uifactory.Create("TextLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = Color3.fromRGB(25, 25, 25),
        TextSize = 16,
        Font = Enum.Font.SourceSansBold,
        ZIndex = 73,
    }, box)

    local label = uifactory.Text(row, def.Name, 16)
    label.Position = UDim2.fromOffset(34, 0)
    label.Size = UDim2.new(1, -40, 1, 0)
    label.ZIndex = 72
    label.TextTruncate = Enum.TextTruncate.AtEnd

    row.MouseEnter:Connect(function()
        row.BackgroundTransparency = 0
        row.BackgroundColor3 = theme.Hover
    end)

    row.MouseLeave:Connect(function()
        row.BackgroundTransparency = 1
    end)

    row.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        toolactions.Settings.SetOption(def, not toolactions.Settings.GetOption(def))
    end)

    local function refresh()
        local enabled = toolactions.Settings.GetOption(def) == true

        box.BackgroundColor3 =
            enabled
            and Color3.fromRGB(238, 238, 238)
            or Color3.fromRGB(35, 37, 41)

        check.Text = enabled and "✓" or ""

        label.TextColor3 =
            toolactions.Settings.SaveOptions[def.Name] ~= nil
            and theme.Accent2
            or theme.Text
    end

    table.insert(toolactions.Settings.OptionRefreshers, refresh)
    refresh()
end

toolactions.Settings.CreateOptionValue = function(def, y)
    local label = uifactory.Text(toolactions.Settings.Content, def.Name, 16)
    label.Position = UDim2.fromOffset(14, y)
    label.Size = UDim2.new(1, -150, 0, 28)
    label.ZIndex = 62
    label.TextTruncate = Enum.TextTruncate.AtEnd

    local control

    if def.Type == "choice" then
        control = uifactory.Create("TextButton", {
            Position = UDim2.new(1, -126, 0, y + 2),
            Size = UDim2.fromOffset(114, 24),
            BackgroundColor3 = Color3.fromRGB(29, 29, 29),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            TextColor3 = theme.Text,
            TextSize = 15,
            Font = Enum.Font.SourceSans,
            ZIndex = 62,
        }, toolactions.Settings.Content)

        control.MouseButton1Click:Connect(function()
            local current = tostring(toolactions.Settings.GetOption(def))
            local nextindex = 1

            for i, choice in def.Choices do
                if choice == current then
                    nextindex = i % #def.Choices + 1
                    break
                end
            end

            toolactions.Settings.SetOption(def, def.Choices[nextindex])
        end)
    else
        control = uifactory.Create("TextBox", {
            Position = UDim2.new(1, -126, 0, y + 2),
            Size = UDim2.fromOffset(114, 24),
            BackgroundColor3 = Color3.fromRGB(29, 29, 29),
            BorderSizePixel = 0,
            ClearTextOnFocus = false,
            PlaceholderText =
                def.Default ~= nil
                and tostring(def.Default)
                or def.Placeholder
                or "default",
            PlaceholderColor3 = Color3.fromRGB(110, 110, 110),
            Text = "",
            TextColor3 = theme.Text,
            TextSize = 15,
            Font = Enum.Font.SourceSans,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ZIndex = 62,
        }, toolactions.Settings.Content)
        uifactory.Create("UIPadding", {
            PaddingLeft = UDim.new(0, 5),
            PaddingRight = UDim.new(0, 5),
        }, control)

        control.FocusLost:Connect(function()
            local text = runtimeutil.Trim(control.Text)

            if text == "" then
                toolactions.Settings.SetOption(def, nil)
            elseif def.Type == "number" then
                local number = tonumber(text)

                if number then
                    toolactions.Settings.SetOption(def, number)
                else
                    toolactions.Settings.SetOption(def, toolactions.Settings.SaveOptions[def.Name])
                end
            else
                toolactions.Settings.SetOption(def, text)
            end
        end)
    end

    uifactory.Round(control, 4)
    uifactory.Stroke(control, theme.BorderSoft)

    local function refresh()
        local override = toolactions.Settings.SaveOptions[def.Name]

        if def.Type == "choice" then
            control.Text = tostring(toolactions.Settings.GetOption(def))
        elseif not control:IsFocused() then
            control.Text = override ~= nil and tostring(override) or ""
        end

        label.TextColor3 =
            override ~= nil
            and theme.Accent2
            or theme.Text
    end

    table.insert(toolactions.Settings.OptionRefreshers, refresh)
    refresh()
end

do
    local y = 136

    for _, group in toolactions.Settings.OptionGroups do
        if group[1] ~= "" then
            toolactions.Settings.CreateSection(group[1], y)
            y += 28
        end

        for _, def in group[2] do
            toolactions.Settings.OptionDefs[def.Name] = def

            if def.Type == "bool" then
                toolactions.Settings.CreateOptionToggle(def, y)
            else
                toolactions.Settings.CreateOptionValue(def, y)
            end

            y += 28
        end

        y += 8
    end

    toolactions.Settings.SaveButton.Position = UDim2.fromOffset(12, y)
    toolactions.Settings.ResetButton.Position = UDim2.fromOffset(12, y + 36)

    toolactions.Settings.Content.CanvasSize = UDim2.fromOffset(0, y + 36 + 24 + 12)
end

toolactions.Settings.ResetButton.MouseButton1Click:Connect(function()
    table.clear(toolactions.Settings.SaveOptions)
    toolactions.Settings.Save()

    for _, refresh in toolactions.Settings.OptionRefreshers do
        refresh()
    end
end)

toolactions.Settings.BuildSaveOptions = function()
    local options = {}

    for name, value in toolactions.Settings.SaveOptions do
        if name == "CompressionMode" and value == "false" then
            options[name] = false
        elseif name == "IgnoreProperties" then
            local list = {}

            for token in tostring(value):gmatch("[^,]+") do
                local trimmed = runtimeutil.Trim(token)

                if trimmed ~= "" then
                    list[#list + 1] = trimmed
                end
            end

            if #list > 0 then
                options[name] = list
            end
        else
            options[name] = value
        end
    end

    return options
end

toolactions.Settings.SaveInstance = function()
    local settingsstate = toolactions.Settings

    if settingsstate.SaveBusy or not adapter.saveinstance then
        return
    end

    settingsstate.SaveBusy = true
    settingsstate.SaveButton.Text = "Saving..."

    task.spawn(function()
        local options = settingsstate.BuildSaveOptions()
        local filename = ("Place_%s_%s"):format(
            tostring(rawgame.PlaceId),
            os.date("%d-%m-%Y_%H-%M-%S")
        )

        local ok, err = pcall(adapter.saveinstance, rawgame, filename, options)

        if not ok then
            warn("[Explorer] saveinstance failed: " .. tostring(err))
        end

        settingsstate.SaveBusy = false

        if settingsstate.SaveButton and settingsstate.SaveButton.Parent then
            settingsstate.SaveButton.Text = "Save Game"
        end
    end)
end

toolactions.Settings.SaveButton.MouseButton1Click:Connect(toolactions.Settings.SaveInstance)

toolactions.Settings.Close = function()
    toolactions.Settings.Frame.Visible = false
    settings:SetAttribute("Active", false)
    settings.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
    settingsicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
end

toolactions.Settings.Open = function()
    propertycontroller.CloseDropdown()
    toolactions.CloseColorPicker()

    if toolactions.ClosePropertyMenu then
        toolactions.ClosePropertyMenu()
    end

    menucontroller.Close()

    if toolactions.CloseCredits then
        toolactions.CloseCredits()
    end

    toolactions.Settings.Frame.Visible = true
    settings:SetAttribute("Active", true)
    settings.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    settingsicon.ImageColor3 = theme.Accent
end

toolactions.Settings.Load()

for key in toolactions.Settings.Toggles do
    toolactions.Settings.RefreshToggle(key)
end

for _, refresh in toolactions.Settings.OptionRefreshers do
    refresh()
end

settings.MouseButton1Click:Connect(function()
    if toolactions.Settings.Frame.Visible then
        toolactions.Settings.Close()
    else
        toolactions.Settings.Open()
    end
end)

toolactions.SelectionVisual = {}

toolactions.SelectionVisual.Box = uifactory.Create("SelectionBox", {
    Name = "SelectionBox",
    Color3 = theme.Accent,
    LineThickness = 0.03,
    SurfaceColor3 = theme.Accent,
    SurfaceTransparency = 0.85,
}, rootgui)

toolactions.SelectionVisual.Outline = uifactory.Create("Frame", {
    Name = "SelectionOutline",
    Visible = false,
    Active = false,
    BackgroundColor3 = theme.Accent,
    BackgroundTransparency = 0.85,
    BorderSizePixel = 0,
    ZIndex = 60,
}, rootgui)

uifactory.Create("UIStroke", {
    Color = theme.Accent,
    Thickness = 2,
    ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, toolactions.SelectionVisual.Outline)

toolactions.UpdateSelectionVisual = function()
    local visual = toolactions.SelectionVisual
    local obj = selectednode and selectednode.obj
    local isinstance = typeof(obj) == "Instance"

    local adornee = nil

    if isinstance
        and (obj:IsA("BasePart") or obj:IsA("Model"))
        and not obj:IsA("Terrain")
        and obj:IsDescendantOf(workspace)
    then
        adornee = obj
    end

    if visual.Box.Adornee ~= adornee then
        visual.Box.Adornee = adornee
    end

    local showoutline = false

    if isinstance
        and obj:IsA("GuiObject")
        and obj.Visible
        and not obj:IsDescendantOf(rootgui)
    then
        local layer = obj:FindFirstAncestorWhichIsA("LayerCollector")

        if layer and layer:IsA("ScreenGui") and layer.Enabled then
            local pos = obj.AbsolutePosition

            if not layer.IgnoreGuiInset then
                pos += (dockcontroller.GetGuiInsets())
            end

            visual.Outline.Position = UDim2.fromOffset(pos.X, pos.Y)
            visual.Outline.Size = UDim2.fromOffset(
                obj.AbsoluteSize.X,
                obj.AbsoluteSize.Y
            )
            showoutline = true
        end
    end

    if visual.Outline.Visible ~= showoutline then
        visual.Outline.Visible = showoutline
    end
end

toolactions.SelectionVisual.Connection = runservice.Heartbeat:Connect(function()
    if not rootgui.Parent then
        toolactions.SelectionVisual.Connection:Disconnect()
        return
    end

    toolactions.UpdateSelectionVisual()
end)

toolactions.PointInside = function(gui, point)
    if not gui or not gui.Visible then
        return false
    end

    local pos = gui.AbsolutePosition
    local size = gui.AbsoluteSize

    return point.X >= pos.X
        and point.X <= pos.X + size.X
        and point.Y >= pos.Y
        and point.Y <= pos.Y + size.Y
end

toolactions.IsPointerOverExplorer = function(point)
    return toolactions.PointInside(main, point)
        or toolactions.PointInside(toolactions.ColorPicker.Frame, point)
        or toolactions.PointInside(contextmenu, point)
        or toolactions.PointInside(submenu, point)
        or (
            toolactions.ViewerUI.Overlay.Visible
            and toolactions.PointInside(toolactions.ViewerUI.Window, point)
        )
end

toolactions.IsVisualGui = function(obj)
    if obj.BackgroundTransparency < 1 then
        return true
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        return obj.Text ~= "" and obj.TextTransparency < 1
    end

    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        return obj.Image ~= "" and obj.ImageTransparency < 1
    end

    return obj:IsA("ViewportFrame") or obj:IsA("VideoFrame")
end

toolactions.GetGuiAtPoint = function(point)
    local playergui = localplayer and localplayer:FindFirstChildOfClass("PlayerGui")

    if not playergui then
        return nil
    end

    local inset = dockcontroller.GetGuiInsets()
    local best = nil
    local bestorder = nil

    local function consider(objects, ignoreinset)
        for _, obj in objects do
            if not obj:IsDescendantOf(rootgui) and toolactions.IsVisualGui(obj) then
                local layer = obj:FindFirstAncestorWhichIsA("LayerCollector")

                if layer
                    and layer:IsA("ScreenGui")
                    and layer.IgnoreGuiInset == ignoreinset
                then
                    if best == nil or layer.DisplayOrder > bestorder then
                        best = obj
                        bestorder = layer.DisplayOrder
                    end

                    return
                end
            end
        end
    end

    local okstandard, standard = pcall(
        playergui.GetGuiObjectsAtPosition,
        playergui,
        point.X - inset.X,
        point.Y - inset.Y
    )

    if okstandard then
        consider(standard, false)
    end

    local okignore, ignoring = pcall(
        playergui.GetGuiObjectsAtPosition,
        playergui,
        point.X,
        point.Y
    )

    if okignore then
        consider(ignoring, true)
    end

    return best
end

toolactions.GetPartAtPoint = function(point)
    local camera = workspace.CurrentCamera

    if not camera then
        return nil
    end

    local ray = camera:ViewportPointToRay(point.X, point.Y)
    local result = workspace:Raycast(ray.Origin, ray.Direction * 5000)

    return result and result.Instance
end

uis.InputBegan:Connect(function(input, processed)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end

    if not rootgui.Parent then
        return
    end

    local mouse = uis:GetMouseLocation()
    local values = toolactions.Settings.Values

    if not (values.ClickPartToSelect or values.ClickUIToSelect) then
        return
    end

    if toolactions.IsPointerOverExplorer(mouse) then
        return
    end

    if toolactions.Settings.Frame.Visible then
        toolactions.Settings.Close()
    end

    if toolactions.CreditsFrame and toolactions.CreditsFrame.Visible then
        toolactions.CloseCredits()
    end

    if values.ClickUIToSelect then
        local gui = toolactions.GetGuiAtPoint(mouse)

        if gui then
            toolactions.JumpToInstance(gui)
            return
        end
    end

    if values.ClickPartToSelect and not processed then
        local part = toolactions.GetPartAtPoint(mouse)

        if part then
            toolactions.JumpToInstance(part)
        end
    end
end)

function treecontroller.GetDisplay(node)
    if node.pseudo then
        return node.name, node.className
    end
    return node.obj.Name, node.obj.ClassName
end

function treecontroller.HasChildren(node)
    if node.pseudo then
        if node == nilroot and not node.loaded then
            return true
        end
        return node.hasChildren == true or #node.children > 0
    end

    if node.hasChildren ~= nil then
        return node.hasChildren
    end

    if node.loaded then
        node.hasChildren = #node.children > 0
        return node.hasChildren
    end

    local ok, children = pcall(function()
        return node.obj:GetChildren()
    end)

    node.hasChildren = ok and #children > 0 or false
    return node.hasChildren
end

function iconcontroller.DownloadIcon(classname: string): string?
    for _, source in studioassetsources do
        local bytes = adapter:HttpBytes(source.Icons .. classname .. ".png")

        if type(bytes) == "string" and #bytes > 8 and bytes:sub(2, 4) == "PNG" then
            return bytes
        end
    end

    return nil
end

local currentstudioiconcache = {}
local currentstudioiconpending = {}
local currentstudioiconfailed = {}

function iconcontroller.GetSafeFileName(classname: string): string
    return tostring(classname):gsub("[^%w_%-%+]", "_") .. ".png"
end

function iconcontroller.EnsureFolders()
    if not adapter.makefolder then return end
    pcall(adapter.makefolder, "Explorer")
    pcall(adapter.makefolder, "Explorer/icons")
    pcall(adapter.makefolder, "Explorer/icons/current")
end

function iconcontroller.GetCurrentPath(classname: string): string
    return "Explorer/icons/current/" .. iconcontroller.GetSafeFileName(classname)
end

function iconcontroller.FileExists(path: string): boolean
    if adapter.isfile then
        local ok, result = pcall(adapter.isfile, path)
        return ok and result == true
    end

    if adapter.readfile then
        local ok = pcall(adapter.readfile, path)
        return ok
    end

    return false
end

function iconcontroller.GetCustomAsset(path: string): string?
    if not adapter.getcustomasset then
        return nil
    end

    local ok, asset = pcall(adapter.getcustomasset, path)
    if ok and type(asset) == "string" and asset ~= "" then
        return asset
    end

    return nil
end

function iconcontroller.ApplyCurrentAsset(imagelabel, asset)
    if not asset then return false end

    imagelabel.Visible = true
    imagelabel.Image = asset

    imagelabel.ImageRectOffset = Vector2.zero
    imagelabel.ImageRectSize = Vector2.zero
    imagelabel.ScaleType = Enum.ScaleType.Fit
    imagelabel.ImageColor3 = Color3.new(1, 1, 1)
    imagelabel.ImageTransparency = 0

    return true
end

function iconcontroller.LoadCached(classname)
    local cached = currentstudioiconcache[classname]
    if cached then
        return cached
    end

    if not (adapter.getcustomasset and adapter.writefile) then
        return nil
    end

    local path = iconcontroller.GetCurrentPath(classname)
    if not iconcontroller.FileExists(path) then
        return nil
    end

    local asset = iconcontroller.GetCustomAsset(path)
    if asset then
        currentstudioiconcache[classname] = asset
        return asset
    end

    return nil
end

function iconcontroller.Resolve(classname: string): string?
    local cached = currentstudioiconcache[classname]
        or iconcontroller.LoadCached(classname)

    if cached then
        return cached
    end

    if currentstudioiconfailed[classname] then
        return nil
    end

    if not (adapter.getcustomasset and adapter.writefile) then
        currentstudioiconfailed[classname] = true
        return nil
    end

    iconcontroller.EnsureFolders()

    local path = iconcontroller.GetCurrentPath(classname)
    local asset = nil

    if iconcontroller.FileExists(path) then
        asset = iconcontroller.GetCustomAsset(path)
    end

    if not asset then
        local bytes = iconcontroller.DownloadIcon(classname)

        local ispng =
            type(bytes) == "string"
            and #bytes > 8
            and bytes:sub(2, 4) == "PNG"

        if ispng then
            local wrote = pcall(adapter.writefile, path, bytes)
            if wrote then
                asset = iconcontroller.GetCustomAsset(path)
            end
        end
    end

    if asset then
        currentstudioiconcache[classname] = asset
        return asset
    end

    currentstudioiconfailed[classname] = true
    return nil
end

function iconcontroller.CollectClassNames(): {string}
    local seen = {}
    local names = {}

    local function addclass(classname)
        if classname and not seen[classname] then
            seen[classname] = true
            names[#names + 1] = classname
        end
    end

    addclass("DataModel")

    local okroots, roots = pcall(function()
        return rawgame:GetChildren()
    end)

    if okroots then
        for _, obj in roots do
            addclass(obj.ClassName)
        end
    end

    local okdesc, desc = pcall(function()
        return rawgame:GetDescendants()
    end)

    if okdesc then
        for _, obj in desc do
            addclass(obj.ClassName)
        end
    end

    table.sort(names)
    return names
end

local iconsprewarmed = false
local iconwarmupstats: IconWarmupState = {
    Total = 0,
    Ready = 0,
    Failed = 0,
    Completed = 0,
    Current = "",
}

function iconcontroller.Prewarm()
    if iconsprewarmed then
        return
    end

    loadingoverlay.Visible = true
    loadingcontroller.SetIconProgress(0, 0, "Scanning game classes...")

    if not (adapter.getcustomasset and adapter.writefile) then
        loadingcontroller.SetStage(
            95,
            "Custom assets unavailable — using fallback icons",
            "fallback icons"
        )
        task.wait(0.05)
        iconsprewarmed = true
        return
    end

    local classnames = iconcontroller.CollectClassNames()
    iconwarmupstats.Total = #classnames
    iconwarmupstats.Ready = 0
    iconwarmupstats.Failed = 0
    iconwarmupstats.Completed = 0
    iconwarmupstats.Current = ""

    loadingcontroller.SetIconProgress(0, #classnames, "Preparing Studio icons...")

    local nextindex = 1
    local active = 0
    local doneevent = Instance.new("BindableEvent")
    local workers = math.min(8, math.max(1, #classnames))

    local function worker()
        while true do
            local idx = nextindex
            nextindex += 1

            if idx > #classnames then
                break
            end

            local classname = classnames[idx]
            iconwarmupstats.Current = classname

            local asset

            if currentstudioiconcache[classname]
                or iconcontroller.FileExists(iconcontroller.GetCurrentPath(classname))
            then
                asset = true
            else
                asset = iconcontroller.Resolve(classname)
            end

            if asset then
                iconwarmupstats.Ready += 1
            else
                iconwarmupstats.Failed += 1
            end

            iconwarmupstats.Completed += 1

            task.defer(function()
                if loadingoverlay and loadingoverlay.Parent then
                    loadingcontroller.SetIconProgress(
                        iconwarmupstats.Completed,
                        iconwarmupstats.Total,
                        ("Preparing icon: %s"):format(classname)
                    )
                end
            end)
        end

        active -= 1
        if active <= 0 then
            doneevent:Fire()
        end
    end

    for _ = 1, workers do
        active += 1
        task.spawn(worker)
    end

    if active > 0 then
        doneevent.Event:Wait()
    end

    doneevent:Destroy()
    iconsprewarmed = true

    loadingcontroller.SetIconProgress(
        iconwarmupstats.Total,
        iconwarmupstats.Total,
        ("Icons ready • %d loaded • %d fallback"):format(
            iconwarmupstats.Ready,
            iconwarmupstats.Failed
        )
    )
end

function iconcontroller.Queue(classname, imagelabel)
    if currentstudioiconpending[classname]
        or currentstudioiconfailed[classname]
        or currentstudioiconcache[classname]
    then
        return
    end

    if not (adapter.getcustomasset and adapter.writefile) then
        currentstudioiconfailed[classname] = true
        return
    end

    currentstudioiconpending[classname] = true

    task.spawn(function()
        iconcontroller.EnsureFolders()

        local path = iconcontroller.GetCurrentPath(classname)
        local asset = nil

        if iconcontroller.FileExists(path) then
            asset = iconcontroller.GetCustomAsset(path)
        end

        if not asset then
            local bytes = iconcontroller.DownloadIcon(classname)

            local ispng =
                type(bytes) == "string"
                and #bytes > 8
                and bytes:sub(2, 4) == "PNG"

            if ispng then
                local wrote = pcall(adapter.writefile, path, bytes)
                if wrote then
                    asset = iconcontroller.GetCustomAsset(path)
                end
            end
        end

        currentstudioiconpending[classname] = nil

        if asset then
            currentstudioiconcache[classname] = asset

            if imagelabel
                and imagelabel.Parent
                and imagelabel:GetAttribute("_ExplorerCurrentClass") == classname
            then
                iconcontroller.ApplyCurrentAsset(imagelabel, asset)
            end
        else
            currentstudioiconfailed[classname] = true
        end
    end)
end

function iconcontroller.ApplyCurrent(imagelabel, classname)
    imagelabel:SetAttribute("_ExplorerCurrentClass", classname)

    local cached = currentstudioiconcache[classname]
        or iconcontroller.LoadCached(classname)

    if cached then
        return iconcontroller.ApplyCurrentAsset(imagelabel, cached)
    end

    if iconsprewarmed then
        iconcontroller.Queue(classname, imagelabel)
    end

    return false
end

local dex_explorer_sheet = "rbxassetid://483448923"
local studio_class_sheet = "rbxasset://textures/ClassImages.PNG"

local dex_class_icon = {
    Accessory = 32,
    Accoutrement = 32,
    AdService = 73,
    Animation = 60,
    AnimationController = 60,
    AnimationTrack = 60,
    Animator = 60,
    ArcHandles = 56,
    AssetService = 72,
    Attachment = 34,
    Backpack = 20,
    BadgeService = 75,
    BallSocketConstraint = 89,
    BillboardGui = 64,
    BinaryStringValue = 4,
    BindableEvent = 67,
    BindableFunction = 66,
    BlockMesh = 8,
    BloomEffect = 90,
    BlurEffect = 90,
    BodyAngularVelocity = 14,
    BodyForce = 14,
    BodyGyro = 14,
    BodyPosition = 14,
    BodyThrust = 14,
    BodyVelocity = 14,
    BoolValue = 4,
    BoxHandleAdornment = 54,
    BrickColorValue = 4,
    Camera = 5,
    CFrameValue = 4,
    CharacterMesh = 60,
    Chat = 33,
    ClickDetector = 41,
    CollectionService = 30,
    Color3Value = 4,
    ColorCorrectionEffect = 90,
    ConeHandleAdornment = 54,
    Configuration = 58,
    ContentProvider = 72,
    ContextActionService = 41,
    CoreGui = 46,
    CoreScript = 18,
    CornerWedgePart = 1,
    CustomEvent = 4,
    CustomEventReceiver = 4,
    CylinderHandleAdornment = 54,
    CylinderMesh = 8,
    CylindricalConstraint = 89,
    Debris = 30,
    Decal = 7,
    Dialog = 62,
    DialogChoice = 63,
    DoubleConstrainedValue = 4,
    Explosion = 36,
    FileMesh = 8,
    Fire = 61,
    Flag = 38,
    FlagStand = 39,
    FloorWire = 4,
    Folder = 70,
    ForceField = 37,
    Frame = 48,
    GamePassService = 19,
    Glue = 34,
    GuiButton = 52,
    GuiMain = 47,
    GuiService = 47,
    Handles = 53,
    HapticService = 84,
    Hat = 45,
    HingeConstraint = 89,
    Hint = 33,
    HopperBin = 22,
    HttpService = 76,
    Humanoid = 9,
    ImageButton = 52,
    ImageLabel = 49,
    InsertService = 72,
    IntConstrainedValue = 4,
    IntValue = 4,
    JointInstance = 34,
    JointsService = 34,
    Keyframe = 60,
    KeyframeSequence = 60,
    KeyframeSequenceProvider = 60,
    Lighting = 13,
    LineHandleAdornment = 54,
    LocalScript = 18,
    LogService = 87,
    MarketplaceService = 46,
    Message = 33,
    Model = 2,
    ModuleScript = 71,
    Motor = 34,
    Motor6D = 34,
    MoveToConstraint = 89,
    NegateOperation = 78,
    NetworkClient = 16,
    NetworkReplicator = 29,
    NetworkServer = 15,
    NumberValue = 4,
    ObjectValue = 4,
    Pants = 44,
    ParallelRampPart = 1,
    Part = 1,
    ParticleEmitter = 69,
    PartPairLasso = 57,
    PathfindingService = 37,
    Platform = 35,
    Player = 12,
    PlayerGui = 46,
    Players = 21,
    PlayerScripts = 82,
    PointLight = 13,
    PointsService = 83,
    Pose = 60,
    PrismaticConstraint = 89,
    PrismPart = 1,
    PyramidPart = 1,
    RayValue = 4,

    ReflectionMetadata = 86,
    ReflectionMetadataCallbacks = 86,
    ReflectionMetadataClass = 86,
    ReflectionMetadataClasses = 86,
    ReflectionMetadataEnum = 86,
    ReflectionMetadataEnumItem = 86,
    ReflectionMetadataEnums = 86,
    ReflectionMetadataEvents = 86,
    ReflectionMetadataFunctions = 86,
    ReflectionMetadataMember = 86,
    ReflectionMetadataProperties = 86,
    ReflectionMetadataYieldFunctions = 86,

    RemoteEvent = 80,
    RemoteFunction = 79,
    ReplicatedFirst = 72,
    ReplicatedStorage = 72,
    RightAngleRampPart = 1,
    RocketPropulsion = 14,
    RodConstraint = 89,
    RopeConstraint = 89,
    Rotate = 34,
    RotateP = 34,
    RotateV = 34,
    RunService = 66,
    ScreenGui = 47,
    Script = 6,
    ScrollingFrame = 48,
    Seat = 35,
    Selection = 55,
    SelectionBox = 54,
    SelectionPartLasso = 57,
    SelectionPointLasso = 57,
    SelectionSphere = 54,
    ServerScriptService = 0,
    ServerStorage = 74,
    Shirt = 43,
    ShirtGraphic = 40,
    SkateboardPlatform = 35,
    Sky = 28,
    SlidingBallConstraint = 89,
    Smoke = 59,
    Snap = 34,
    Sound = 11,
    SoundService = 31,
    Sparkles = 42,
    SpawnLocation = 25,
    SpecialMesh = 8,
    SphereHandleAdornment = 54,
    SpotLight = 13,
    SpringConstraint = 89,
    StarterCharacterScripts = 82,
    StarterGear = 20,
    StarterGui = 46,
    StarterPack = 20,
    StarterPlayer = 88,
    StarterPlayerScripts = 82,
    Status = 2,
    StringValue = 4,
    SunRaysEffect = 90,
    SurfaceGui = 64,
    SurfaceLight = 13,
    SurfaceSelection = 55,
    Team = 24,
    Teams = 23,
    TeleportService = 81,
    Terrain = 65,
    TerrainRegion = 65,
    TestService = 68,
    TextBox = 51,
    TextButton = 51,
    TextLabel = 50,
    Texture = 10,
    TextureTrail = 4,
    Tool = 17,
    TouchTransmitter = 37,
    TrussPart = 1,
    UnionOperation = 77,
    UserInputService = 84,
    Vector3Value = 4,
    VehicleSeat = 35,
    VelocityMotor = 34,
    WedgePart = 1,
    Weld = 34,
    Workspace = 19,
}

local generic_icon = {
    Service = dex_class_icon.CollectionService or 30,
    Instance = dex_class_icon.Folder or 70,
    Gui = dex_class_icon.Frame or 48,
    Value = dex_class_icon.StringValue or 4,
    Script = dex_class_icon.ModuleScript or 71,
    Part = dex_class_icon.Part or 1,
    Constraint = dex_class_icon.BallSocketConstraint or 89,
    Effect = dex_class_icon.BloomEffect or 90,
}

function iconcontroller.FindInheritedDexIcon(classname)
    local current = classname
    local visited = {}

    while current and not visited[current] do
        visited[current] = true

        local icon = dex_class_icon[current]
        if icon ~= nil then
            return icon
        end

        current = metadata:GetSuperclassName(current)
    end

    return nil
end

function iconcontroller.GetGenericDexIcon(classname)
    if metadata:IsServiceClass(classname) then
        return generic_icon.Service
    end

    if classname:find("Gui")
        or classname == "Frame"
        or classname == "TextLabel"
        or classname == "TextButton"
        or classname == "TextBox"
        or classname == "ImageLabel"
        or classname == "ImageButton"
    then
        return generic_icon.Gui
    end

    if classname:find("Value$") then
        return generic_icon.Value
    end

    if classname:find("Script") then
        return generic_icon.Script
    end

    if classname:find("Part")
        or classname == "BasePart"
        or classname == "MeshPart"
    then
        return generic_icon.Part
    end

    if classname:find("Constraint") then
        return generic_icon.Constraint
    end

    if classname:find("Effect") then
        return generic_icon.Effect
    end

    return generic_icon.Instance
end

function iconcontroller.GetDexRect(iconid)
    local row = math.floor((iconid / 14) % 14)
    local col = math.floor(iconid % 14)

    return Vector2.new(
        3 + col * 18,
        3 + row * 18
    )
end

function iconcontroller.ApplyDex(imagelabel, classname)

    local iconid = dex_class_icon[classname]

    if iconid == nil then
        iconid = iconcontroller.FindInheritedDexIcon(classname)
    end

    if iconid ~= nil then
        imagelabel.Visible = true
        imagelabel.Image = dex_explorer_sheet
        imagelabel.ScaleType = Enum.ScaleType.Crop
        imagelabel.ImageRectSize = Vector2.new(16, 16)
        imagelabel.ImageRectOffset = iconcontroller.GetDexRect(iconid)
        imagelabel.ImageColor3 = Color3.new(1, 1, 1)
        imagelabel.ImageTransparency = 0
        return true
    end

    local rmdindex = metadata:GetExplorerImageIndex(classname)
    if rmdindex ~= nil then
        imagelabel.Visible = true
        imagelabel.Image = studio_class_sheet
        imagelabel.ScaleType = Enum.ScaleType.Crop
        imagelabel.ImageRectSize = Vector2.new(16, 16)
        imagelabel.ImageRectOffset = Vector2.new(rmdindex * 16, 0)
        imagelabel.ImageColor3 = Color3.new(1, 1, 1)
        imagelabel.ImageTransparency = 0
        return true
    end

    iconid = iconcontroller.GetGenericDexIcon(classname)

    imagelabel.Visible = true
    imagelabel.Image = dex_explorer_sheet
    imagelabel.ScaleType = Enum.ScaleType.Crop
    imagelabel.ImageRectSize = Vector2.new(16, 16)
    imagelabel.ImageRectOffset = iconcontroller.GetDexRect(iconid)
    imagelabel.ImageColor3 = Color3.new(1, 1, 1)
    imagelabel.ImageTransparency = 0
    return true
end

function iconcontroller.GetBadge(classname, name)
    if classname == "Workspace" then return "WS" end
    if classname == "Players" or classname == "Player" then return "PL" end
    if classname == "Lighting" then return "LG" end
    if classname == "ReplicatedStorage" then return "RS" end
    if classname == "ReplicatedFirst" then return "RF" end
    if classname == "StarterGui" then return "SG" end
    if classname == "StarterPack" then return "SP" end
    if classname == "StarterPlayer" then return "SR" end
    if classname == "SoundService" then return "SS" end
    if classname == "TextChatService" or classname == "Chat" then return "CH" end
    if classname == "RunService" then return "RN" end
    if classname == "CollectionService" then return "CL" end
    if classname == "TweenService" then return "TW" end
    if classname == "HttpService" then return "HT" end
    if classname == "MarketplaceService" then return "MK" end
    if classname == "TeleportService" then return "TP" end

    if classname == "LocalScript" then return "LS" end
    if classname == "ModuleScript" then return "MS" end
    if classname == "Script" then return "SC" end

    if classname == "RemoteEvent" then return "RE" end
    if classname == "RemoteFunction" then return "RFn" end
    if classname == "UnreliableRemoteEvent" then return "UR" end
    if classname == "BindableEvent" then return "BE" end
    if classname == "BindableFunction" then return "BF" end

    if classname == "Folder" then return "FD" end
    if classname == "Configuration" then return "CF" end
    if classname == "Model" then return "MD" end
    if classname == "Part" or classname == "MeshPart" or classname == "UnionOperation" or classname == "BasePart" then return "PT" end
    if classname == "Camera" then return "CM" end
    if classname == "Humanoid" then return "HM" end
    if classname == "Tool" then return "TL" end

    if classname:find("Gui") or classname == "Frame" or classname == "TextLabel" or classname == "TextButton" then
        return "UI"
    end

    if classname:find("Value") then
        return "V"
    end

    local s = name or classname or "?"
    local chars = {}
    for c in tostring(s):gmatch("[%a%d]") do
        chars[#chars + 1] = c:upper()
        if #chars >= 2 then break end
    end
    return #chars > 0 and table.concat(chars) or "?"
end

function iconcontroller.GetBadgeColor(classname)
    if classname == "Workspace" then return Color3.fromRGB(66, 121, 86) end
    if classname == "Players" or classname == "Player" then return Color3.fromRGB(68, 120, 170) end
    if classname == "Lighting" then return Color3.fromRGB(165, 145, 68) end
    if classname == "ReplicatedStorage" or classname == "ReplicatedFirst" then return Color3.fromRGB(102, 86, 176) end
    if classname == "StarterGui" or classname == "StarterPack" or classname == "StarterPlayer" then return Color3.fromRGB(87, 128, 174) end

    if classname == "LocalScript" or classname == "ModuleScript" or classname == "Script" then
        return Color3.fromRGB(68, 126, 183)
    end

    if classname == "RemoteEvent" or classname == "RemoteFunction" or classname == "UnreliableRemoteEvent" then
        return Color3.fromRGB(176, 120, 55)
    end

    if classname == "BindableEvent" or classname == "BindableFunction" then
        return Color3.fromRGB(176, 89, 55)
    end

    if classname == "Folder" or classname == "Configuration" then
        return Color3.fromRGB(156, 133, 66)
    end

    if classname == "Model" or classname == "Humanoid" or classname == "Tool" then
        return Color3.fromRGB(80, 150, 123)
    end

    if classname == "Part" or classname == "MeshPart" or classname == "UnionOperation" or classname == "BasePart" then
        return Color3.fromRGB(70, 135, 129)
    end

    if classname:find("Gui") or classname == "Frame" or classname == "TextLabel" or classname == "TextButton" then
        return Color3.fromRGB(141, 87, 177)
    end

    if classname:find("Value") then
        return Color3.fromRGB(128, 128, 128)
    end

    return Color3.fromRGB(78, 106, 132)
end

function iconcontroller.GetClassColor(classname)
    if classname == "Workspace" then return Color3.fromRGB(106, 187, 108) end
    if classname == "Players" or classname == "Player" then return Color3.fromRGB(95, 174, 226) end
    if classname == "RemoteEvent" or classname == "RemoteFunction" or classname == "UnreliableRemoteEvent" then
        return Color3.fromRGB(234, 172, 91)
    end
    if classname == "LocalScript" or classname == "ModuleScript" or classname == "Script" then
        return Color3.fromRGB(121, 190, 255)
    end
    if classname == "Folder" then return Color3.fromRGB(235, 199, 93) end
    if classname:find("Gui") or classname == "Frame" or classname == "TextLabel" or classname == "TextButton" then
        return Color3.fromRGB(198, 135, 234)
    end
    if classname == "Part" or classname == "MeshPart" or classname == "BasePart" then
        return Color3.fromRGB(129, 204, 196)
    end
    return Color3.fromRGB(135, 174, 210)
end

local lastrenderedstart = nil
local lastrenderedvisiblecount = -1

function treecontroller.Render(force: boolean?)
    local start = math.max(
        1,
        math.floor(treescroll.CanvasPosition.Y / row_h) + 1
    )

    if force == false
        and start == lastrenderedstart
        and #visiblenodes == lastrenderedvisiblecount
    then
        return
    end

    lastrenderedstart = start
    lastrenderedvisiblecount = #visiblenodes

    treescroll.CanvasSize = UDim2.fromOffset(0, #visiblenodes * row_h)
    countlabel.Text = ("%d visible"):format(#visiblenodes)

    for i, r in treerows do
        local idx = start + i - 1
        local node = visiblenodes[idx]

        if node then
            r.Root.Visible = true
            r.Root.Position = UDim2.fromOffset(0, (idx - 1) * row_h)
            r.Root:SetAttribute("NodeIndex", idx)
            local isselected = toolactions.Selection.Set[node] == true
            r.Root.BackgroundTransparency = isselected and 0 or 1
            r.Root.BackgroundColor3 = isselected and theme.Selected or theme.Panel

            local name, classname = treecontroller.GetDisplay(node)
            local depth = math.max(0, node.depth or 0)
            local hc = treecontroller.HasChildren(node)

            r.Expand.Visible = hc
            r.Expand.Text = node.expanded and "▼" or "▶"
            r.Expand.Position = UDim2.fromOffset(3 + depth * 18, 0)

            local iconx = 21 + depth * 18

            r.Icon.Position = UDim2.fromOffset(iconx, math.floor((row_h - 16) / 2))
            r.Badge.Position = UDim2.fromOffset(iconx, math.floor((row_h - 12) / 2))

            if iconcontroller.ApplyCurrent(r.Icon, classname)
                or iconcontroller.ApplyDex(r.Icon, classname)
            then
                r.Badge.Visible = false
                r.BadgeText.Visible = false
            else
                r.Badge.Visible = true
                r.BadgeText.Visible = true
                r.Badge.BackgroundColor3 = iconcontroller.GetBadgeColor(classname)
                r.BadgeText.Text = iconcontroller.GetBadge(classname, name)
            end

            r.Label.Position = UDim2.fromOffset(42 + depth * 18, 0)
            r.Label.Size = UDim2.new(1, -(46 + depth * 18), 1, 0)
            r.Label.Text = name
            r.Label.TextColor3 =
                (classname == "RemoteEvent" or classname == "RemoteFunction" or classname == "UnreliableRemoteEvent")
                and Color3.fromRGB(239, 187, 112)
                or theme.Text
        else
            r.Root.Visible = false
            r.Root:SetAttribute("NodeIndex", nil)
        end
    end
end

for _, r in treerows do
    r.Root.MouseButton1Click:Connect(function()
        local idx = r.Root:GetAttribute("NodeIndex")
        local node = idx and visiblenodes[idx]
        if node then
            local ctrl = uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)
            local shift = uis:IsKeyDown(Enum.KeyCode.LeftShift) or uis:IsKeyDown(Enum.KeyCode.RightShift)

            if shift then
                treecontroller.SelectRange(node)
            elseif ctrl then
                treecontroller.ToggleNode(node)
            else
                treecontroller.SelectNode(node)
            end

            treecontroller.Render()
        end
    end)

    r.Root.MouseButton2Click:Connect(function()
        local idx = r.Root:GetAttribute("NodeIndex")
        local node = idx and visiblenodes[idx]

        if node then
            if not toolactions.Selection.Set[node] then
                treecontroller.SelectNode(node)
                treecontroller.Render()
            end

            local pos = uis:GetMouseLocation()
            menucontroller.Open(node, pos)
        end
    end)

    r.Expand.MouseButton1Click:Connect(function()
        local idx = r.Root:GetAttribute("NodeIndex")
        local node = idx and visiblenodes[idx]
        if node then
            node.expanded = not node.expanded
            if node.expanded then
                if node.pseudo then treecontroller.LoadNilChildren() else treecontroller.LoadChildren(node) end
            end
            treecontroller.BuildVisible()
            treecontroller.Render(true)
        end
    end)
end

treescroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
    treecontroller.Render(false)
end)

function treecontroller.Search(text: string, generation: number)
    text = runtimeutil.Trim(text):lower()

    if text == "" then
        searchmode = false
        treecontroller.BuildVisible()
        treecontroller.Render()
        statuslabel.Text = metadata.Ready and ("API " .. metadata.Version) or (metadata.Error or "metadata unavailable")
        return
    end

    searchmode = true
    local results = {}
    local ok, descs = pcall(function() return rawgame:GetDescendants() end)
    if not ok then return end

    local maxresults = 1500
    for _, obj in descs do
        if generation ~= searchgeneration then return end

        local n = obj.Name:lower()
        local c = obj.ClassName:lower()
        if n:find(text, 1, true) or c:find(text, 1, true) then
            local node = treecontroller.GetOrCreateNode(obj, nil)
            node.depth = 0
            results[#results + 1] = node
            if #results >= maxresults then break end
        end
    end

    if generation ~= searchgeneration then return end

    visiblenodes = results
    treescroll.CanvasPosition = Vector2.zero
    treecontroller.Render()
    statuslabel.Text = ("Search: %d result%s"):format(#results, #results == 1 and "" or "s")
end

search:GetPropertyChangedSignal("Text"):Connect(function()
    searchgeneration += 1
    local gen = searchgeneration
    task.delay(0.22, function()
        if gen == searchgeneration then
            treecontroller.Search(search.Text, gen)
        end
    end)
end)

toolactions._liveTreeRefreshPending = false
toolactions._dirtyParents = {}

toolactions.QueueLiveTreeRefresh = function(parentnode)
    if parentnode then
        toolactions._dirtyParents[parentnode] = true
    end

    if toolactions._liveTreeRefreshPending then
        return
    end

    toolactions._liveTreeRefreshPending = true

    task.delay(0.04, function()
        toolactions._liveTreeRefreshPending = false

        for parent in toolactions._dirtyParents do
            if parent and parent.children then
                if #parent.children > 1 then
                    table.sort(parent.children, treecontroller.CompareNodes)
                end
                parent.sortDirty = false
                parent.hasChildren = #parent.children > 0
            end
            toolactions._dirtyParents[parent] = nil
        end

        if not searchmode then
            treecontroller.BuildVisible()
            treecontroller.Render(true)
        end
    end)
end

rawgame.DescendantAdded:Connect(function(obj)

    if iconsprewarmed
        and not currentstudioiconcache[obj.ClassName]
        and not currentstudioiconfailed[obj.ClassName]
        and adapter.getcustomasset
        and adapter.writefile
    then
        task.spawn(function()
            iconcontroller.Resolve(obj.ClassName)
            if not searchmode then
                treecontroller.Render(true)
            end
        end)
    end

    local parentobj = obj.Parent
    local parentnode = parentobj and nodesbyobject[parentobj]

    if parentnode then
        parentnode.hasChildren = true
    end

    if parentnode and parentnode.loaded then
        local n = treecontroller.GetOrCreateNode(obj, parentnode)
        local found = false

        for _, child in parentnode.children do
            if child == n then
                found = true
                break
            end
        end

        if not found then
            parentnode.children[#parentnode.children + 1] = n
            parentnode.sortDirty = true
        end

        toolactions.QueueLiveTreeRefresh(parentnode)
    end
end)

rawgame.DescendantRemoving:Connect(function(obj)
    local node = nodesbyobject[obj]
    if not node then
        return
    end

    local parentnode = node.parent

    if parentnode and parentnode.children then
        local idx = table.find(parentnode.children, node)
        if idx then
            table.remove(parentnode.children, idx)
        end

        parentnode.hasChildren = #parentnode.children > 0
        parentnode.sortDirty = true
    end

    nodesbyobject[obj] = nil

    treecontroller.RemoveFromSelection(node)

    toolactions.QueueLiveTreeRefresh(parentnode)
end)

toolactions.Refresh = function()
    root.loaded = false
    root.hasChildren = nil
    root.sortDirty = false
    table.clear(root.children)
    treecontroller.LoadChildren(root)

    if nilroot then
        nilroot.loaded = false
        nilroot.hasChildren = nil
        nilroot.sortDirty = false
        table.clear(nilroot.children)
    end

    searchmode = false
    search.Text = ""
    treecontroller.BuildVisible()
    treescroll.CanvasPosition = Vector2.zero
    treecontroller.Render()
    statuslabel.Text = metadata.Ready and ("API " .. metadata.Version .. " • refreshed") or "Tree refreshed"
end

toolactions.SortLoadedTree = function(node)
    if node and node.loaded and node.children then
        table.sort(node.children, treecontroller.CompareNodes)

        for _, child in node.children do
            toolactions.SortLoadedTree(child)
        end
    end
end

bodyui.Visible = false
loadingoverlay.Visible = true
statuslabel.Text = "Preparing Explorer..."
loadingcontroller.SetStage(0, "Starting...", "")

pcall(function()
    runservice.RenderStepped:Wait()
end)

loadingcontroller.SetStage(5, "Loading Roblox API metadata...", "API")
statuslabel.Text = "Loading Roblox API metadata..."

metadata._loadOK = metadata:Load()

if metadata._loadOK then
    if metadata.RMDReady then
        loadingcontroller.SetStage(25, "Reflection metadata ready", "API + RMD")
        statuslabel.Text = "API + ReflectionMetadata ready"
    else
        loadingcontroller.SetStage(25, "API ready • Reflection metadata unavailable", "API")
        statuslabel.Text = "API ready • RMD unavailable"
    end
else

    loadingcontroller.SetStage(25, metadata.Error or "Metadata unavailable", "fallback order")
    statuslabel.Text = metadata.Error or "metadata unavailable"
end

toolactions.SortLoadedTree(root)

if nilroot and nilroot.loaded then
    table.sort(nilroot.children, treecontroller.CompareNodes)
end

iconcontroller.Prewarm()

loadingcontroller.SetStage(97, "Finalizing Explorer order...", "sorting")
toolactions.SortLoadedTree(root)

if nilroot and nilroot.loaded then
    table.sort(nilroot.children, treecontroller.CompareNodes)
end

treecontroller.BuildVisible()
treecontroller.Render()

if selectednode then
    propertycontroller.Rebuild()
    propertycontroller.Render()
end

loadingcontroller.SetStage(
    100,
    "Ready",
    metadata.RMDReady and "ordered + icons" or "ready"
)

bodyui.Visible = true

if metadata._loadOK then
    statuslabel.Text = metadata.RMDReady
        and ("API " .. metadata.Version .. " • ordered")
        or ("API " .. metadata.Version .. " • fallback order")
end

task.wait(0.12)
loadingoverlay.Visible = false

local explorerapp = {}
explorerapp.__index = explorerapp

function explorerapp.new()
    return setmetatable({
        Gui = rootgui,
        Main = main,
        LoadingOverlay = loadingoverlay,
        MainSizeConstraint = mainsizeconstraint,
        ScreenBounds = screenbounds,
        Adapter = adapter,
        Metadata = metadata,
        CurrentStudioIconCache = currentstudioiconcache,
        IconWarmupStats = iconwarmupstats,
        HasCustomAsset = adapter.getcustomasset ~= nil,
        HasFileWrite = adapter.writefile ~= nil,
        HasHttpRequest = adapter.request ~= nil,
    }, explorerapp)
end

function explorerapp:Select(value: any, candidate: Instance?)
    local obj = candidate or value
    if typeof(obj) ~= "Instance" then return end
    local node = nodesbyobject[obj] or treecontroller.GetOrCreateNode(obj, nil)
    treecontroller.SelectNode(node)
    treecontroller.Render()
end

function explorerapp:Refresh()
    toolactions.Refresh()
end

function explorerapp:PrewarmIcons(): IconWarmupState
    iconsprewarmed = false
    iconwarmupstats.Total = 0
    iconwarmupstats.Ready = 0
    iconwarmupstats.Failed = 0
    iconwarmupstats.Completed = 0
    iconwarmupstats.Current = ""
    iconcontroller.Prewarm()
    toolactions.SortLoadedTree(root)
    treecontroller.BuildVisible()
    treecontroller.Render()
    return iconwarmupstats
end

function explorerapp:DockRight()
    dockcontroller.DockRight()
    dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
    resizegrip.Visible = false
    dockresize.Visible = true
end

function explorerapp:Undock()
    dockcontroller.Undock()
    dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
    resizegrip.Visible = true
    dockresize.Visible = false
end

function explorerapp:SetRespectGuiInset(value: any, candidate: boolean?)
    local enabled = candidate ~= nil and candidate or value
    dock.RespectGuiInset = enabled == true
    if dock.Docked then dockcontroller.ApplyRightDock() end
end

function explorerapp:SetBottomOverscan(value: any, candidate: number?)
    local px = candidate ~= nil and candidate or value
    dock.BottomOverscan = math.max(0, tonumber(px) or 0)
    if dock.Docked then dockcontroller.ApplyRightDock() end
end

function explorerapp:GetDockState()
    return {
        ScreenBoundsSize = screenbounds.AbsoluteSize,
        ScreenBoundsPosition = screenbounds.AbsolutePosition,
        MainSize = main.AbsoluteSize,
        MainPosition = main.AbsolutePosition,
        Parent = tostring(rootgui.Parent),
        Docked = dock.Docked,
        Collapsed = dock.Collapsed,
    }
end

function explorerapp:GetDockDebug()
    return self:GetDockState()
end

function explorerapp:Destroy()
    runtimeutil.Disconnect(propertychangedconn)
    runtimeutil.Disconnect(toolactions.PropertyRealtimeConnection)
    if rootgui then rootgui:Destroy() end
end

local app = explorerapp.new()
toolactions.Public = app

if type(getgenv) == "function" then
    getgenv().Explorer = app
end

return app