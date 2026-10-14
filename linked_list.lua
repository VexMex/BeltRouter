-- A reusable list whose entries are joined by previous/next links.
-- Each node stores {value, previousNode, nextNode}; it does not calculate routes.
-- This helper is not imported by the current routing modules.

-- Adapted from https://github.com/iskolbin/linkedlist/blob/master/LinkedList.lua

local assert, abs, setmetatable = assert, math.abs, setmetatable

--- @class LinkedList
--- @type LinkedList
local LinkedList = {}

-- A shared marker means "no neighbor"; it is different from Lua's nil value.
local Nil = {}

local LinkedListMt

-- Create a list and, if given an array, link its values together in order.
function LinkedList.new( array )
    local self = {
        _head = Nil,
        _tail = Nil,
        _length = 0,
    }

    if array then
        local len = #array
        if len > 0 then
            local node = {array[1],Nil,Nil}
            self._head = node
            for i = 2, len do
                local nextnode = {array[i],node,Nil}
                node[3] = nextnode
                node = nextnode
            end
            self._tail = node
            self._length = len
        end
    end

    return setmetatable( self, LinkedListMt )
end

-- Copy the node structure into a new list; stored values themselves are still shared.
function LinkedList:copy()
    local result = LinkedList.new()
    local node = self._head
    while node ~= Nil do
        result:insert( node[1] )
        node = node[3]
    end
    return result
end

-- Read a numbered value; positive indexes count from the front, negative ones from the back.
function LinkedList:index( i )
    local len = self._length
    assert( abs(i) - 1 <= len and i ~= 0, 'bad argument #1 to \'index\' (position out of bounds)')
    local node = Nil
    if i > 0 then
        node = self._head
        for j = 1, i-1 do
            node = node[3]
        end
    else
        node = self._tail
        for j = 1, -i-1 do
            node = node[2]
        end
    end
    return node[1]
end


-- Find a numbered node and replace its stored value.
function LinkedList:set( i, v )
    local len = self._length
    assert( abs(i) - 1 <= len and i ~= 0, 'bad argument #1 to \'index\' (position out of bounds)')
    local node = Nil
    if i > 0 then
        node = self._head
        for j = 1, i-1 do
            node = node[3]
        end
    else
        node = self._tail
        for j = 1, -i-1 do
            node = node[2]
        end
    end
    node[1] = v
end

-- Accept insert(value) or insert(index, value), then join a new node to its neighbors.
function LinkedList:insert( i_or_v, v_ )
    assert( i_or_v ~= nil, 'wrong number of arguments to \'insert\'' )
    local v = v_ or i_or_v
    local i = ( v_ ~= nil ) and i_or_v or -1
    local len = self._length
    assert( abs(i) - 1 <= len and i ~= 0, 'bad argument #2 to \'insert\' (position out of bounds)')

    if len == 0 then
        self._length = 1
        self._head = {v, Nil, Nil}
        self._tail = self._head
    else
        if i == len+1 then
            i = -1
        elseif i == -len-1 then
            i = 1
        end
        self._length = len + 1
        if i > 0 then
            local node = self._head
            for j = 1, i-1 do
                node = node[3]
            end
            local newnode = {v,node[2],node}
            if node[2] ~= Nil then
                node[2][3] = newnode
            else
                self._head = newnode
            end
            node[2] = newnode

        else
            local node = self._tail
            for j = 1, -i-1 do
                node = node[2]
            end
            local newnode = {v,node,node[3]}
            if node[3] ~= Nil then
                node[3][2] = newnode
            else
                self._tail = newnode
            end
            node[3] = newnode
        end
    end

    return self
end

-- Remove a numbered node and reconnect its neighbors; the default is the last node.
function LinkedList:remove( i_ )
    local i = i_ or -1
    local len = self._length
    assert( abs(i) <= len and i ~= 0, 'bad argument #2 to \'insert\' (position out of bounds)')

    if len == 1 then
        local v = self._head[1]
        self._length = 0
        self._head = Nil
        self._tail = Nil
        return v
    else
        if i == len then
            i = -1
        elseif i == -len then
            i = 1
        end

        self._length = len - 1

        if i == 1 then
            local v = self._head[1]
            self._head = self._head[3]
            self._head[2] = Nil
            return v
        elseif i == -1 then
            local v = self._tail[1]
            self._tail = self._tail[2]
            self._tail[3] = Nil
            return v
        else
            local node

            if i > 0 then
                node = self._head
                for j = 1, i-1 do
                    node = node[3]
                end
            else
                node = self._tail
                for j = 1, -i-1 do
                    node = node[2]
                end
            end

            local v = node[1]
            -- Join the previous and next nodes directly so the removed node is no longer in the chain.
            node[2][3], node[3][2] = node[3], node[2]
            return v
        end
    end
end

-- Return the saved entry count instead of walking through all nodes.
function LinkedList:len()
    return self._length
end

-- Swap each node's previous/next links, then swap the front and back pointers.
function LinkedList:reverse()
    local len = self._length
    if len > 1 then
        local node = self._head
        for i = 1, len do
            local nextnode = node[3]
            node[2], node[3] = node[3], node[2]
            node = nextnode
        end
        self._head, self._tail = self._tail, self._head
    end
    return self
end

-- Copy the selected range of values into a new linked list.
function LinkedList:sub( i, j_ )
    local len = self._length
    assert( abs(i) <= len, 'bad argument #2 to \'sub\' (position out of bounds)')
    local j = j_ or -1
    assert( abs(j) <= len, 'bad argument #3 to \'sub\' (position out of bounds)')
    local fromnode, tonode

    if i > 0 then
        fromnode = self._head
        for i_ = 2, i do
            fromnode = fromnode[3]
        end
    else
        fromnode = self._tail
        for i_ = 2, -i do
            fromnode = fromnode[2]
        end
    end

    if j > 0 then
        tonode = self._head
        for j_ = 2, j do
            tonode = tonode[3]
        end
    else
        tonode = self._tail
        for j_ = 2, -j do
            tonode = tonode[2]
        end
    end

    local result = LinkedList.new()
    while fromnode ~= tonode[3] do
        result:insert( fromnode[1] )
        fromnode = fromnode[3]
    end

    return result
end

-- Walk forward through the nodes and format their values as text.
function LinkedList:tostring()
    local t, node = {}, self._head
    for i = 1, self._length do
        t[i], node = tostring( node[1] ), node[3]
    end
    return '{' .. table.concat( t, ',' ) .. '}'
end

-- Walk forward through the nodes and put their values into a normal Lua list.
function LinkedList:toarray()
    local t, node = {}, self._head
    for i = 1, self._length do
        t[i], node = node[1], node[3]
    end
    return t
end

-- Insert a value at the front.
function LinkedList:pushhead( v )
    return self:insert( 1, v )
end

-- This helper name is defined twice below; the later definition replaces the earlier one.
function LinkedList:pophead( v )
    return self:remove( 1, v )
end

-- Insert a value at the back.
function LinkedList:pushtail( v )
    return self:insert( -1, v )
end

-- This helper name is defined twice below; the later definition replaces the earlier one.
function LinkedList:pophead( v )
    return self:remove( -1, v )
end

-- Read the last value without removing it.
function LinkedList:peektail()
    assert( self._length > 0, 'list is empty' )
    return self._tail[1]
end

-- Read the first value without removing it.
function LinkedList:peekhead()
    assert( self._length > 0, 'list is empty' )
    return self._head[1]
end

-- Advance one node and return its numbered value for list iteration.
local function ipairsiter( state, index )
    local node = state[1]
    if node ~= Nil then
        state[1] = node[3]
        return index + 1, node[1]
    end
end

-- Return an iterator that follows next-node links and produces numbered values.
function LinkedList:ipairs()
    return ipairsiter, {self._head}, 0
end

-- Attach the other list's nodes to this list, then empty the other list.
function LinkedList:merge( list )
    local len = list._length
    if len > 0 then
        self._tail[3] = list._head
        self._tail = list._tail
        self._length = self._length + len
        list._head = Nil
        list._tail = Nil
        list._length = 0
    end
    return self
end

-- Provide familiar alternative names for the operations above; these are method aliases.
LinkedList.push = LinkedList.pushtail
LinkedList.pop = LinkedList.poptail
LinkedList.enqueue = LinkedList.pushhead
LinkedList.dequeue = LinkedList.poptail
LinkedList.peek = LinkedList.peektail
LinkedList.shift = LinkedList.pushhead
LinkedList.unshift = LinkedList.pophead

LinkedListMt = {
    __index = LinkedList,
    __len = LinkedList.len,
    __tostring = LinkedList.tostring,
    __ipairs = LinkedList.ipairs,
}

--- @return LinkedList
return setmetatable( LinkedList, {
    __call = function( _, ... )
        return LinkedList.new( ... )
    end
} )