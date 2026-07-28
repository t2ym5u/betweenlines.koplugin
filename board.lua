local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire_common(name)
    local key = _dir .. "common/" .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. "common/" .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local grid_utils       = lrequire_common("grid_utils")
local puzzle_generator = lrequire_common("puzzle_generator")
local BaseBoard        = lrequire_common("base_board")

local emptyGrid        = grid_utils.emptyGrid
local emptyNotes       = grid_utils.emptyNotes
local emptyMarkerGrid  = grid_utils.emptyMarkerGrid
local copyGrid         = grid_utils.copyGrid
local copyNotes        = grid_utils.copyNotes

local generateSolvedBoard = puzzle_generator.generateSolvedBoard
local createPuzzle        = puzzle_generator.createPuzzle

-- ---------------------------------------------------------------------------
-- Grid config (9x9 only)
-- ---------------------------------------------------------------------------

local GRID_CONFIGS = {
    { id = "9x9", n = 9, box_rows = 3, box_cols = 3, label = "9\xC3\x979" },
}

local function getGridConfig(id)
    return GRID_CONFIGS[1]
end

local DEFAULT_DIFFICULTY = "medium"

-- ---------------------------------------------------------------------------
-- Between-lines placement helpers
-- ---------------------------------------------------------------------------

-- Place 4-6 "between lines" on the solution grid.
-- Each line: { cells = {{r,c},...} }
--   cells[1]  and cells[#cells] are the two endpoint bulbs (different values).
--   All intermediate cells must have values strictly between the two endpoints.
-- Returns the list of lines.
local function placeBetweenLines(solution)
    local n = 9
    -- All 8 compass directions -- using only the 4 "forward" ones (right/
    -- down/both down-diagonals) left corner cells unreachable as a path
    -- cell (arriving at a corner would require a source with a negative
    -- row/col), so lines clustered heavily toward the grid's center and
    -- almost never touched the corner boxes. All 8 directions make every
    -- cell reachable from some source, spreading lines across the whole
    -- grid.
    local directions = {
        { dr = 0,  dc = 1  },  -- right
        { dr = 0,  dc = -1 },  -- left
        { dr = 1,  dc = 0  },  -- down
        { dr = -1, dc = 0  },  -- up
        { dr = 1,  dc = 1  },  -- diag down-right
        { dr = 1,  dc = -1 },  -- diag down-left
        { dr = -1, dc = 1  },  -- diag up-right
        { dr = -1, dc = -1 },  -- diag up-left
    }

    local lines     = {}
    local cell_used = {}

    local function cellKey(r, c) return r * 100 + c end

    -- Even with all 8 directions available, uniformly-random start-cell
    -- placement still favors the grid's center: any bounded-length path
    -- dropped at a random position/orientation in a bounded grid is more
    -- likely to fit (not go out of bounds) the closer its start is to the
    -- center -- a general geometric effect, not specific to this game.
    -- Since the target count (4-6) never exceeds the 9 boxes, assign
    -- each line to its own shuffled box up front and require its start
    -- cell to land there -- this guarantees real spread rather than
    -- merely nudging the odds (a soft inverse-touch-count bias was tried
    -- and found too weak: a start cell biased toward a corner box still
    -- mostly extends its path *into* the center anyway).
    local box_order = {}
    for br = 1, 3 do for bc = 1, 3 do box_order[#box_order + 1] = { br = br, bc = bc } end end
    for i = #box_order, 2, -1 do
        local j = math.random(i)
        box_order[i], box_order[j] = box_order[j], box_order[i]
    end

    local function randomCellInBox(box)
        local row_in_box = math.random(0, 2)
        local col_in_box = math.random(0, 2)
        return (box.br - 1) * 3 + row_in_box + 1, (box.bc - 1) * 3 + col_in_box + 1
    end

    -- Try to place one line with its start cell restricted to `box` (nil
    -- = anywhere). Returns true and appends to `lines` on success.
    local function tryPlaceOne(box)
        local sr, sc
        if box then
            sr, sc = randomCellInBox(box)
        else
            sr, sc = math.random(1, n), math.random(1, n)
        end
        if cell_used[cellKey(sr, sc)] then return false end

        local dir    = directions[math.random(#directions)]
        local length = math.random(4, 5)  -- total cells including both endpoints

        local path = { { r = sr, c = sc } }
        for i = 1, length - 1 do
            local nr = sr + dir.dr * i
            local nc = sc + dir.dc * i
            if nr < 1 or nr > n or nc < 1 or nc > n then return false end
            if cell_used[cellKey(nr, nc)] then return false end
            path[#path + 1] = { r = nr, c = nc }
        end
        if #path < 4 then return false end

        -- Check: endpoints must have different values
        local v_start = solution[path[1].r][path[1].c]
        local v_end   = solution[path[#path].r][path[#path].c]
        if v_start == v_end then return false end

        -- Check: all intermediate values must be strictly between the endpoint values
        local lo = math.min(v_start, v_end)
        local hi = math.max(v_start, v_end)
        for i = 2, #path - 1 do
            local v = solution[path[i].r][path[i].c]
            if v <= lo or v >= hi then return false end
        end

        for _, cell in ipairs(path) do
            cell_used[cellKey(cell.r, cell.c)] = true
        end
        lines[#lines + 1] = { cells = path }
        return true
    end

    local target_count = math.random(4, 6)
    local box_sub_attempts = 250

    for i = 1, target_count do
        local box = box_order[i]
        local placed = false
        for _ = 1, box_sub_attempts do
            if tryPlaceOne(box) then placed = true; break end
        end
        if not placed then
            -- This box couldn't fit one (rare -- e.g. heavily used by
            -- earlier lines); fall back to a free placement anywhere so
            -- the target count is still reached.
            for _ = 1, box_sub_attempts * 2 do
                if tryPlaceOne(nil) then break end
            end
        end
    end

    return lines
end

-- ---------------------------------------------------------------------------
-- BetweenLinesBoard
-- ---------------------------------------------------------------------------

local BetweenLinesBoard = setmetatable({}, { __index = BaseBoard })
BetweenLinesBoard.__index = BetweenLinesBoard

function BetweenLinesBoard:new(config)
    local n        = 9
    local box_rows = 3
    local box_cols = 3
    local board = {
        n               = n,
        box_rows        = box_rows,
        box_cols        = box_cols,
        grid_id         = "9x9",
        puzzle          = emptyGrid(n),
        solution        = emptyGrid(n),
        user            = emptyGrid(n),
        conflicts       = emptyGrid(n),
        notes           = emptyNotes(n),
        wrong_marks     = emptyMarkerGrid(n),
        selected        = { row = 1, col = 1 },
        difficulty      = DEFAULT_DIFFICULTY,
        reveal_solution = false,
        undo_stack      = {},
        lines           = {},
    }
    setmetatable(board, self)
    board:recalcConflicts()
    return board
end

function BetweenLinesBoard:serialize()
    local n = self.n
    -- Serialize lines
    local lines_data = {}
    for i, line in ipairs(self.lines) do
        local cells_data = {}
        for j, cell in ipairs(line.cells) do
            cells_data[j] = { r = cell.r, c = cell.c }
        end
        lines_data[i] = { cells = cells_data }
    end
    return {
        n               = n,
        box_rows        = self.box_rows,
        box_cols        = self.box_cols,
        grid_id         = self.grid_id,
        puzzle          = copyGrid(self.puzzle, n),
        solution        = copyGrid(self.solution, n),
        user            = copyGrid(self.user, n),
        notes           = copyNotes(self.notes, n),
        wrong_marks     = copyGrid(self.wrong_marks, n),
        selected        = { row = self.selected.row, col = self.selected.col },
        difficulty      = self.difficulty,
        reveal_solution = self.reveal_solution,
        lines           = lines_data,
    }
end

function BetweenLinesBoard:load(state)
    if not state or not state.puzzle or not state.solution or not state.user then
        return false
    end
    self.n        = state.n        or 9
    self.box_rows = state.box_rows or 3
    self.box_cols = state.box_cols or 3
    self.grid_id  = state.grid_id  or "9x9"
    local n = self.n
    self.puzzle      = copyGrid(state.puzzle, n)
    self.solution    = copyGrid(state.solution, n)
    self.user        = copyGrid(state.user, n)
    self.notes       = copyNotes(state.notes, n)
    self.wrong_marks = state.wrong_marks and copyGrid(state.wrong_marks, n) or emptyMarkerGrid(n)
    self.conflicts   = emptyGrid(n)
    self.difficulty  = state.difficulty or DEFAULT_DIFFICULTY
    self.undo_stack  = {}
    if state.selected then
        self.selected = {
            row = math.max(1, math.min(n, state.selected.row or 1)),
            col = math.max(1, math.min(n, state.selected.col or 1)),
        }
    else
        self.selected = { row = 1, col = 1 }
    end
    self.reveal_solution = state.reveal_solution or false
    -- Load lines
    self.lines = {}
    if state.lines then
        for i, ld in ipairs(state.lines) do
            local cells = {}
            for j, cell in ipairs(ld.cells) do
                cells[j] = { r = cell.r, c = cell.c }
            end
            self.lines[i] = { cells = cells }
        end
    end
    self:recalcConflicts()
    return true
end

function BetweenLinesBoard:generate(difficulty)
    self.difficulty = difficulty or self.difficulty or DEFAULT_DIFFICULTY
    local n, box_rows, box_cols = self.n, self.box_rows, self.box_cols
    local solution = generateSolvedBoard(n, box_rows, box_cols)
    local puzzle   = createPuzzle(solution, self.difficulty, n, box_rows, box_cols)
    self.puzzle          = puzzle
    self.solution        = solution
    self.user            = emptyGrid(n)
    self.notes           = emptyNotes(n)
    self.wrong_marks     = emptyMarkerGrid(n)
    self.selected        = { row = 1, col = 1 }
    self.reveal_solution = false
    self.undo_stack      = {}
    self.lines           = placeBetweenLines(solution)
    self:recalcConflicts()
end

function BetweenLinesBoard:isGiven(row, col)
    return self.puzzle[row][col] ~= 0
end

function BetweenLinesBoard:getWorkingValue(row, col)
    local given = self.puzzle[row][col]
    if given ~= 0 then return given end
    return self.user[row][col]
end

function BetweenLinesBoard:getDisplayValue(row, col)
    if self.reveal_solution then
        return self.solution[row][col], self:isGiven(row, col)
    end
    if self:isGiven(row, col) then
        return self.puzzle[row][col], true
    end
    local value = self.user[row][col]
    if value == 0 then return nil end
    return value, false
end

function BetweenLinesBoard:checkLine(line)
    local cells = line.cells
    if #cells < 4 then return end
    -- Check if all cells are filled
    for _, cell in ipairs(cells) do
        if self:getWorkingValue(cell.r, cell.c) == 0 then return end
    end
    -- Get endpoint values
    local v_start = self:getWorkingValue(cells[1].r, cells[1].c)
    local v_end   = self:getWorkingValue(cells[#cells].r, cells[#cells].c)
    local lo = math.min(v_start, v_end)
    local hi = math.max(v_start, v_end)
    -- Check intermediate cells
    local has_violation = false
    for i = 2, #cells - 1 do
        local v = self:getWorkingValue(cells[i].r, cells[i].c)
        if v <= lo or v >= hi then
            self.conflicts[cells[i].r][cells[i].c] = true
            has_violation = true
        end
    end
    -- If any intermediate violated, also mark endpoints
    if has_violation then
        self.conflicts[cells[1].r][cells[1].c]           = true
        self.conflicts[cells[#cells].r][cells[#cells].c] = true
    end
end

function BetweenLinesBoard:recalcConflicts()
    -- Call parent for row/col/box conflicts
    BaseBoard.recalcConflicts(self)
    -- Check between-line violations
    for _, line in ipairs(self.lines or {}) do
        self:checkLine(line)
    end
end

function BetweenLinesBoard:isConflict(row, col)
    return self.conflicts[row][col]
end

function BetweenLinesBoard:clearUndoHistory()
    self.undo_stack = {}
end

return {
    BetweenLinesBoard  = BetweenLinesBoard,
    DEFAULT_DIFFICULTY = DEFAULT_DIFFICULTY,
    GRID_CONFIGS       = GRID_CONFIGS,
    getGridConfig      = getGridConfig,
}
