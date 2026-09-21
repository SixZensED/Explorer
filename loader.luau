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

function metadataprovider:LoadReflectionMetadata(): boolean
    local cachepath = "Explorer/reflection_metadata.xml"
    local raw = cachestore.Read(cachepath)

    if not raw then
        raw = cachestore.HttpGet(
            "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml"
        )
    end

    if not raw then
        return false
    end

    cachestore.Write(cachepath, raw)

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
    local version = cachestore.HttpGet("https://setup.roblox.com/versionQTStudio")
    if version then
        version = runtimeutil.Trim(version)
        self.Version = version
    end

    local cachepath = "Explorer/api_" .. tostring(self.Version):gsub("[^%w%-_]", "_") .. ".json"
    local raw = cachestore.Read(cachepath)

    if not raw and version then
        raw = cachestore.HttpGet("https://setup.roblox.com/" .. version .. "-API-Dump.json")
    end

    if not raw then
        raw = cachestore.HttpGet("https://raw.githubusercontent.com/infyiff/backup/refs/heads/main/rbx_api.dat")
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

    cachestore.Write(cachepath, raw)

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
title.Size = UDim2.new(1, -88, 1, 0)
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
    Position = UDim2.new(1, -84, 0, 0),
    Size = UDim2.fromOffset(84, 28),
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

local collapse = uifactory.Create("ImageButton", {
    Name = "Collapse",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(33, 36, 41),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 0),
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
    Image = "rbxassetid://71093547857106",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = collapse.ZIndex + 1,
}, collapse)

collapse.MouseEnter:Connect(function()
    collapse.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    collapseicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

collapse.MouseLeave:Connect(function()
    collapse.BackgroundColor3 = Color3.fromRGB(33, 36, 41)
    collapseicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
end)

local docktop = uifactory.Create("ImageButton", {
    Name = "DockTop",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(33, 36, 41),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(28, 0),
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
    Image = "rbxassetid://129039782394959",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = docktop.ZIndex + 1,
}, docktop)

local close = uifactory.Create("ImageButton", {
    Name = "Close",
    AutoButtonColor = false,
    BackgroundTransparency = 0,
    BackgroundColor3 = Color3.fromRGB(33, 36, 41),
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(56, 0),
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
    Image = "rbxassetid://103660394764868",
    ImageColor3 = Color3.fromRGB(235, 235, 235),
    ScaleType = Enum.ScaleType.Fit,
    ZIndex = close.ZIndex + 1,
}, close)

docktop.MouseEnter:Connect(function()
    docktop.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    dockicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

docktop.MouseLeave:Connect(function()
    docktop.BackgroundColor3 = Color3.fromRGB(33, 36, 41)
    dockicon.ImageColor3 = Color3.fromRGB(235, 235, 235)
end)

close.MouseEnter:Connect(function()
    close.BackgroundColor3 = Color3.fromRGB(50, 53, 59)
    closeicon.ImageColor3 = Color3.fromRGB(255, 255, 255)
end)

close.MouseLeave:Connect(function()
    close.BackgroundColor3 = Color3.fromRGB(33, 36, 41)
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

local prop_canvas_min_w = 760
local prop_name_w = 280

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
    Image = "rbxassetid://103660394764868",
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
        "Place_"
        .. tostring(rawgame.PlaceId)
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
        TextSize = 12,
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
        if node and node ~= selectednode then
            row.BackgroundTransparency = 0
            row.BackgroundColor3 = theme.Hover
        end
    end)

    row.MouseLeave:Connect(function()
        local node = row:GetAttribute("NodeIndex") and visiblenodes[row:GetAttribute("NodeIndex")]
        if node ~= selectednode then
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

    local width = math.max(
        220,
        propertycontroller.GetViewportWidth() - prop_name_w - 8
    )

    local itemheight = 24
    local height = math.min(240, #items * itemheight + 2)
    local localx =
        row.AbsolutePosition.X
        - propertiespane.AbsolutePosition.X
        + prop_name_w
        + 4

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
    Size = UDim2.fromOffset(300, 270),
    ZIndex = 70,
}, propertiespane)
uifactory.Stroke(toolactions.ColorPicker.Frame, theme.Border)

toolactions.ColorPicker.Title = uifactory.Text(
    toolactions.ColorPicker.Frame,
    "Color3",
    15
)
toolactions.ColorPicker.Title.Position = UDim2.fromOffset(8, 0)
toolactions.ColorPicker.Title.Size = UDim2.new(1, -36, 0, 28)
toolactions.ColorPicker.Title.ZIndex = 71

toolactions.ColorPicker.Close = uifactory.Create("TextButton", {
    Position = UDim2.new(1, -28, 0, 0),
    Size = UDim2.fromOffset(28, 28),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Text = "×",
    TextColor3 = theme.Text,
    TextSize = 17,
    Font = Enum.Font.SourceSans,
    ZIndex = 72,
}, toolactions.ColorPicker.Frame)

toolactions.ColorPicker.SVBase = uifactory.Create("Frame", {
    Position = UDim2.fromOffset(10, 34),
    Size = UDim2.fromOffset(190, 150),
    BackgroundColor3 = Color3.fromHSV(0, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)

toolactions.ColorPicker.SVWhite = uifactory.Create("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 72,
}, toolactions.ColorPicker.SVBase)

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
    Size = UDim2.fromOffset(10, 10),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 75,
}, toolactions.ColorPicker.SVBase)
uifactory.Round(toolactions.ColorPicker.SVMarker, 5)
uifactory.Stroke(toolactions.ColorPicker.SVMarker, Color3.new(1, 1, 1))

toolactions.ColorPicker.Hue = uifactory.Create("Frame", {
    Position = UDim2.fromOffset(208, 34),
    Size = UDim2.fromOffset(18, 150),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)

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
    Size = UDim2.fromOffset(24, 3),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 74,
}, toolactions.ColorPicker.Hue)

toolactions.ColorPicker.Preview = uifactory.Create("Frame", {
    Position = UDim2.fromOffset(236, 34),
    Size = UDim2.fromOffset(54, 54),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Stroke(toolactions.ColorPicker.Preview, theme.Border)

toolactions.ColorPicker.R = uifactory.Create("TextBox", {
    Position = UDim2.fromOffset(10, 196),
    Size = UDim2.fromOffset(82, 28),
    BackgroundColor3 = theme.Panel2,
    BorderSizePixel = 0,
    Text = "255",
    TextColor3 = theme.Text,
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    ClearTextOnFocus = false,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Stroke(toolactions.ColorPicker.R, theme.BorderSoft)

toolactions.ColorPicker.G = uifactory.Create("TextBox", {
    Position = UDim2.fromOffset(109, 196),
    Size = UDim2.fromOffset(82, 28),
    BackgroundColor3 = theme.Panel2,
    BorderSizePixel = 0,
    Text = "255",
    TextColor3 = theme.Text,
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    ClearTextOnFocus = false,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Stroke(toolactions.ColorPicker.G, theme.BorderSoft)

toolactions.ColorPicker.B = uifactory.Create("TextBox", {
    Position = UDim2.fromOffset(208, 196),
    Size = UDim2.fromOffset(82, 28),
    BackgroundColor3 = theme.Panel2,
    BorderSizePixel = 0,
    Text = "255",
    TextColor3 = theme.Text,
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    ClearTextOnFocus = false,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Stroke(toolactions.ColorPicker.B, theme.BorderSoft)

toolactions.ColorPicker.Hex = uifactory.Create("TextBox", {
    Position = UDim2.fromOffset(10, 232),
    Size = UDim2.new(1, -20, 0, 28),
    BackgroundColor3 = theme.Panel2,
    BorderSizePixel = 0,
    Text = "#FFFFFF",
    TextColor3 = theme.Text,
    TextSize = 14,
    Font = Enum.Font.SourceSans,
    ClearTextOnFocus = false,
    ZIndex = 71,
}, toolactions.ColorPicker.Frame)
uifactory.Stroke(toolactions.ColorPicker.Hex, theme.BorderSoft)

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

    local frame = toolactions.ColorPicker.Frame
    local width = frame.Size.X.Offset
    local height = frame.Size.Y.Offset

    local x =
        row.AbsolutePosition.X
        - propertiespane.AbsolutePosition.X
        + prop_name_w
        + 4

    local y =
        row.AbsolutePosition.Y
        - propertiespane.AbsolutePosition.Y
        + row.AbsoluteSize.Y

    if x + width > propertiespane.AbsoluteSize.X - 4 then
        x = math.max(4, propertiespane.AbsoluteSize.X - width - 4)
    end

    if y + height > propertiespane.AbsoluteSize.Y - 4 then
        y =
            math.max(
                32,
                row.AbsolutePosition.Y
                - propertiespane.AbsolutePosition.Y
                - height
            )
    end

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

    if base.ReadOnly
        or base.Special == "Attribute"
        or base.Special == "Category"
    then
        return
    end

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
            propertycontroller.OpenDropdown(row, p, currentvalue)
        end
    end)

    dropbutton.MouseButton1Click:Connect(function()
        local idx = row:GetAttribute("PropIndex")
        local p = idx and propertylist[idx]
        local currentvalue, readable = toolactions.ReadEntryValue(p)

        if not readable or not p or p.ReadOnly then
            return
        end

        propertycontroller.OpenDropdown(row, p, currentvalue)
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
        elseif valuetype == "EnumItem"
            or valuetype == "BrickColor"
        then
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

    if #attrnames > 0 then
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

            if p.Special == "Category" then
                r.Root.BackgroundColor3 = theme.Panel2
                r.Name.Position = UDim2.fromOffset(5, 0)
                r.Name.Size =
                    UDim2.fromOffset(
                        propertycontroller.GetCanvasWidth() - 10,
                        prop_h
                    )

                r.Name.Text =
                    (p.Collapsed and "▶ " or "▼ ")
                    .. p.Name

                r.Name.TextColor3 = theme.Accent2
                r.Value.Visible = false
                r.ExpandButton.Visible = false
                r.BoolBox.Visible = false
                r.ColorSwatch.Visible = false
                r.RefButton.Visible = false
                r.DropButton.Visible = false
                r.CategoryButton.Visible = true
                r.Sep.Visible = false
                r.Bottom.BackgroundColor3 = theme.Border
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
                    and isinstance
                    and v ~= nil

                r.RefButton.Active =
                    r.RefButton.Visible

                local hasdropdown =
                    isenumitem
                    or isbrickcolor

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

function treecontroller.SelectNode(node)
    propertycontroller.CloseDropdown()
    toolactions.CloseColorPicker()
    toolactions.ClosePropertyMenu()
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

function menucontroller.DuplicateObject(obj)
    if not obj then return end

    local oldarchivable = obj.Archivable
    local clone

    local ok = pcall(function()
        obj.Archivable = true
        clone = obj:Clone()
        clone.Parent = obj.Parent
    end)

    pcall(function()
        obj.Archivable = oldarchivable
    end)

    if ok and clone then
        local parentnode = obj.Parent and nodesbyobject[obj.Parent]
        if parentnode and parentnode.loaded then
            parentnode.loaded = false
            treecontroller.LoadChildren(parentnode)
        end

        treecontroller.BuildVisible()
        treecontroller.Render()
    end
end

local cutbuffer = nil

function menucontroller.CutObject(obj)
    if not obj or obj == rawgame then return end

    cutbuffer = {
        Object = obj,
        Parent = obj.Parent,
        Mode = "Cut",
    }

    pcall(function()
        obj.Parent = nil
    end)

    statuslabel.Text = "Cut: " .. obj.Name .. " • use Paste from Hierarchy"
end

local copybuffer = nil

function menucontroller.CopyObject(obj)
    if not obj or obj == rawgame then return end

    local oldarchivable = obj.Archivable
    local clone

    pcall(function()
        obj.Archivable = true
        clone = obj:Clone()
        obj.Archivable = oldarchivable
    end)

    if clone then
        copybuffer = {
            Object = clone,
            Source = obj,
            Mode = "Copy",
        }
        statuslabel.Text = "Copied: " .. obj.Name
    end
end

function menucontroller.PasteInto(target)
    if not target then return end

    if cutbuffer and cutbuffer.Object then
        local obj = cutbuffer.Object
        pcall(function()
            obj.Parent = target
        end)
        cutbuffer = nil
        statuslabel.Text = "Pasted"
    elseif copybuffer and copybuffer.Object then
        local clone
        pcall(function()
            clone = copybuffer.Object:Clone()
            clone.Parent = target
        end)
        if clone then
            statuslabel.Text = "Pasted copy"
        end
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

function menucontroller.DeleteObject(node)
    if not node.obj or node.obj == rawgame then return end

    pcall(function()
        node.obj:Destroy()
    end)

    menucontroller.Close()
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
            node.loaded = false
            treecontroller.LoadChildren(node)
            treecontroller.BuildVisible()
            treecontroller.Render()
        end
    end, {
        disabled = not (
            (cutbuffer and cutbuffer.Object)
            or (copybuffer and copybuffer.Object)
        )
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

    menucontroller.CreateItem(contextmenu, "Cut", function(node)
        menucontroller.CutObject(node.obj)
    end, {
        disabled = not obj or obj == rawgame
    })

    menucontroller.CreateItem(contextmenu, "Copy", function(node)
        menucontroller.CopyObject(node.obj)
    end, {
        disabled = not obj or obj == rawgame
    })

    menucontroller.CreateItem(contextmenu, "Copy As", nil, {
        submenu = true,
        buildSubmenu = menucontroller.BuildCopyAsMenu,
    })

    menucontroller.SeparatorLine(contextmenu)

    menucontroller.CreateItem(contextmenu, "Duplicate", function(node)
        menucontroller.DuplicateObject(node.obj)
    end, {
        disabled = not obj or obj == rawgame
    })

    menucontroller.CreateItem(contextmenu, "Delete", menucontroller.DeleteObject, {
        disabled = not obj or obj == rawgame
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

local current_studio_icon_base =
    "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/" ..
    "studio-svg-textures/Shared/InsertableObjects/Dark/Standard/"

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
        local url = current_studio_icon_base .. classname .. ".png"
        local bytes = adapter:HttpBytes(url)

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

            local asset = iconcontroller.Resolve(classname)

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
            local url = current_studio_icon_base .. classname .. ".png"
            local bytes = adapter:HttpBytes(url)

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
            r.Root.BackgroundTransparency = node == selectednode and 0 or 1
            r.Root.BackgroundColor3 = node == selectednode and theme.Selected or theme.Panel

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
            treecontroller.SelectNode(node)
            treecontroller.Render()
        end
    end)

    r.Root.MouseButton2Click:Connect(function()
        local idx = r.Root:GetAttribute("NodeIndex")
        local node = idx and visiblenodes[idx]

        if node then
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

    if selectednode == node then
        treecontroller.SelectNode(nil)
    end

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
