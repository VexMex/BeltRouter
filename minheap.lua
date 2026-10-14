-- A priority queue: the item with the smallest score comes out first.
-- The route search uses it for candidates; the task manager uses it for pending work.
-- Unlike normal Lua lists, the internal array starts at index 0.


--- isLessThen
-- @param newNum
-- @param nodeNum
-- @return ok
-- By default, a smaller number means a higher priority in the queue.
local function isLessThen(newNum, nodeNum)
    return newNum < nodeNum;
end

--- @class MinHeapNode
--- @field num number
--- @field val any
--- @field idx number

--- @class MinHeap
--- @type MinHeap
--- @field len number
local MinHeap = {};

-- Move a replacement entry downward until smaller children no longer need to come first.
function MinHeap:heapDown(arr, len, idx)
    -- Keep the moved node aside while smaller children move upward into the gap.
    local node = arr[idx];
    local hsize = math.floor(len / 2);

    while idx < hsize do
        local left = idx * 2 + 1;
        local right = left + 1;
        local child = arr[left];

        if right < len then
            if self.lessFunc(arr[right].num, child.num) then
                left = right;
                child = arr[right];
            end
        end

        if not self.lessFunc(child.num, node.num) then
            break ;
        end

        child.idx = idx;
        arr[idx] = child;
        idx = left;
    end

    node.idx = idx;
    arr[idx] = node;
end


--- @return boolean
-- Check whether any entries remain.
function MinHeap:isEmpty()
    return self.len == 0;
end

--- @return MinHeapNode
-- Read the smallest-score entry without removing it.
function MinHeap:peek()
    return self.arr[0];
end


--- @return MinHeapNode
-- Add a score and value, moving the entry upward until the queue order is restored.
function MinHeap:push(num, val)
    local arr = self.arr;
    local idx = self.len;
    local node = { num = num, val = val, idx = idx };

    self.len = idx + 1;
    arr[idx] = node;

    -- Compare the new entry with its parent and move it toward the front while its score is smaller.
    while idx > 0 do
        local prev = math.floor((idx - 1) / 2);
        local parent = arr[prev];

        if not self.lessFunc(num, parent.num) then
            break ;
        end

        parent.idx = idx;
        arr[idx] = parent;
        idx = prev;
    end

    arr[idx] = node;
    node.idx = idx;

    return node;
end

--- @return MinHeapNode
-- Remove the entry with the smallest score, stored at index 0.
function MinHeap:pop()
    return self:del(0);
end


--- @return MinHeapNode
-- Remove an entry and use the last entry to fill the gap, then adjust it downward.
function MinHeap:del(idx)
    local arr = self.arr;
    -- Keep the moved node aside while smaller children move upward into the gap.
    local node = arr[idx];

    if node then
        local len = self.len - 1;

        if idx == len then
            self.len = len;
            arr[idx] = nil;
        else
            self.len = len;
            -- Fill the removed slot with the final entry, then restore the queue order.
            arr[idx] = arr[len];
            arr[len] = nil;
            self:heapDown(arr, self.len, idx);
        end
    end

    return node;
end

--- @return MinHeap
-- Create an empty queue and choose how scores are compared.
function MinHeap:new(lessThanFunc)
    return setmetatable({
        arr = {},
        len = 0,
        lessFunc = lessThanFunc or isLessThen
    }, {
        __index = self or MinHeap
    })
end

return MinHeap
