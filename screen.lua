local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local function lrequire_common(name)
    local key = _dir .. "common/" .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. "common/" .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local Menu            = require("ui/widget/menu")
local UIManager       = require("ui/uimanager")
local T               = require("ffi/util").template

local _ = require("i18n")

local BetweenLinesBoardWidget = lrequire("board_widget")

local common            = lrequire_common("base_screen")
local BaseScreen        = common.BaseScreen
-- Between Lines only ships 3 difficulty levels (no "expert") -- override the
-- shared 4-level default rather than pulling it from common.
local DIFFICULTY_ORDER  = { "easy", "medium", "hard" }
local DIFFICULTY_LABELS = common.DIFFICULTY_LABELS

local DeviceScreen = Device.screen

local GAME_RULES_EN = _([[
Between Lines Sudoku — Rules

Standard Sudoku rules apply:
• Fill the 9×9 grid with 1–9; each row, column, and 3×3 box must contain each digit exactly once.

Between-lines constraint:
• Lines connect two circle endpoints on the grid.
• Every digit placed on a line must be strictly between (numerically) the values of the two endpoint circles.]])

local GAME_RULES_FR = [[
Sudoku Entre-Lignes — Règles

Les règles du Sudoku classique s'appliquent :
• Remplissez la grille 9×9 avec les chiffres 1 à 9 ; chaque ligne, colonne et carré 3×3 doit contenir chaque chiffre exactement une fois.

Contrainte entre-lignes :
• Des lignes relient deux cercles extrémités sur la grille.
• Chaque chiffre placé sur une ligne doit être strictement compris (numériquement) entre les valeurs des deux cercles extrémités.
]]

local BetweenLinesScreen = BaseScreen:extend{}

function BetweenLinesScreen:buildLayout()
    local title_bar = self:buildTitleBar(_("Between Lines Sudoku"), function()
        return {
            { text = _("New game"),                        callback = function() self:onNewGame() end },
            { text = self:getDifficultyButtonText(),       callback = function() self:openDifficultyMenu() end },
            { text = self.board:isShowingSolution() and _("Hide solution") or _("Show solution"),
                                                           callback = function() self:toggleSolution() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
    local controls = self:buildKeypadControls()
    self.board_widget = BetweenLinesBoardWidget:new{
        board              = self.board,
        max_size           = self:getBoardMaxSize(title_bar, controls),
        onSelectionChanged = function() self:updateStatus() end,
    }
    self:placeBoard(title_bar, self.board_widget, controls)
    self:ensureShowButtonState()
    self:updateNoteButton()
    self:updateUndoButton()
    self:updateDigitButtons()
    self:updateDifficultyButton()
    self:updateStatus()
end

function BetweenLinesScreen:getDifficultyButtonText()
    local label = DIFFICULTY_LABELS[self.board.difficulty] or self.board.difficulty
    return T(_("Difficulty: %1"), label)
end

function BetweenLinesScreen:openDifficultyMenu()
    local menu
    local function selectDifficulty(level)
        if level ~= self.board.difficulty then
            self.board:generate(level)
            self.plugin:saveState()
            self.board_widget:refresh()
            self:ensureShowButtonState()
            self:updateDigitButtons()
            self:updateStatus(T(_("Started a %1 game."), DIFFICULTY_LABELS[level] or level))
        else
            self:updateStatus()
        end
        self:updateDifficultyButton()
        if menu then UIManager:close(menu) end
        return true
    end
    local items = {}
    for _, level in ipairs(DIFFICULTY_ORDER) do
        items[#items + 1] = {
            text     = DIFFICULTY_LABELS[level] or level,
            checked  = (level == self.board.difficulty),
            callback = function() return selectDifficulty(level) end,
        }
    end
    menu = Menu:new{
        title      = _("Select difficulty"),
        item_table = items,
        width      = math.floor(DeviceScreen:getWidth() * 0.7),
        height     = math.floor(DeviceScreen:getHeight() * 0.9),
        disable_footer_padding = true,
        show_parent = self,
    }
    UIManager:show(menu)
end

return BetweenLinesScreen
