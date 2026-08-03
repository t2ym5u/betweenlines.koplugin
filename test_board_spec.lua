local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("BetweenLinesBoard", function()
    local Mod, BetweenLinesBoard

    setup(function()
        Mod = require("board")
        BetweenLinesBoard = Mod.BetweenLinesBoard
    end)

    describe("new", function()
        it("creates a 9x9 board with no lines until generate is called", function()
            local b = BetweenLinesBoard:new()
            assert.are.equal(9, b.n)
            assert.are.equal(0, #b.lines)
        end)
    end)

    describe("generate", function()
        it("fills a valid 9x9 solution and places 4-6 between-lines", function()
            math.randomseed(42)
            local b = BetweenLinesBoard:new()
            b:generate("medium")
            local n = b.n
            for r = 1, n do
                local seen = {}
                for c = 1, n do seen[b.solution[r][c]] = true end
                for d = 1, n do assert.is_true(seen[d], "row " .. r .. " missing " .. d) end
            end
            assert.is_true(#b.lines >= 4 and #b.lines <= 6)
        end)

        it("every line's intermediate values lie strictly between its endpoints", function()
            math.randomseed(11)
            local b = BetweenLinesBoard:new()
            b:generate("medium")
            for _, line in ipairs(b.lines) do
                local cells = line.cells
                local v_start = b.solution[cells[1].r][cells[1].c]
                local v_end   = b.solution[cells[#cells].r][cells[#cells].c]
                assert.are_not.equal(v_start, v_end)
                local lo, hi = math.min(v_start, v_end), math.max(v_start, v_end)
                for i = 2, #cells - 1 do
                    local v = b.solution[cells[i].r][cells[i].c]
                    assert.is_true(v > lo and v < hi)
                end
            end
        end)
    end)

    describe("recalcConflicts (between-line violations)", function()
        it("flags a line whose filled values break the between rule", function()
            math.randomseed(42)
            local b = BetweenLinesBoard:new()
            b:generate("medium")
            local line = b.lines[1]
            local cells = line.cells
            for _, cell in ipairs(cells) do
                if not b:isGiven(cell.r, cell.c) then
                    b.user[cell.r][cell.c] = b.solution[cell.r][cell.c]
                end
            end
            -- Force a violation: set the first intermediate cell equal to an endpoint.
            local mid = cells[2]
            if not b:isGiven(mid.r, mid.c) then
                b.user[mid.r][mid.c] = b.solution[cells[1].r][cells[1].c]
                b:recalcConflicts()
                assert.is_true(b.conflicts[mid.r][mid.c])
            end
        end)
    end)

    describe("serialize / load", function()
        it("round-trips puzzle, solution and lines", function()
            math.randomseed(42)
            local b = BetweenLinesBoard:new()
            b:generate("medium")
            local data = b:serialize()

            local b2 = BetweenLinesBoard:new()
            assert.is_true(b2:load(data))
            assert.are.equal(#b.lines, #b2.lines)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(b.solution[r][c], b2.solution[r][c])
                end
            end
        end)

        it("load returns false for invalid data", function()
            local b = BetweenLinesBoard:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
