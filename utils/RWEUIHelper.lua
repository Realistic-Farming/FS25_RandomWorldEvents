-- =========================================================
-- Random World Events - UI Helper
-- =========================================================
-- Based on the cloning pattern from Worker Costs / Soil Fertilizer
-- =========================================================

RWEUIHelper = RWEUIHelper or {}

local function getTextSafe(key)
    local text = g_i18n:getText(key)
    if text == nil or text == "" then
        return key
    end
    return text
end

function RWEUIHelper.createSection(layout, textId)
    local section = nil
    for _, el in ipairs(layout.elements) do
        if el.name == "sectionHeader" then
            section = el:clone(layout)
            section.id = nil
            section:setText(getTextSafe(textId))
            layout:addElement(section)
            break
        end
    end
    return section
end

function RWEUIHelper.createSubHeader(layout, textId)
    -- Sub-headers usually don't have a template in the base game settings,
    -- so we clone the section header and scale it down if possible, 
    -- or just use another section header.
    local section = nil
    for _, el in ipairs(layout.elements) do
        if el.name == "sectionHeader" then
            section = el:clone(layout)
            section.id = nil
            section:setText(getTextSafe(textId))
            -- If we want it to look different, we could tweak properties here
            layout:addElement(section)
            break
        end
    end
    return section
end

function RWEUIHelper.createBinaryOption(layout, id, textId, state, callback)
    local template = nil

    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild.id and (
                string.find(firstChild.id, "^check") or 
                string.find(firstChild.id, "Check")
            ) then
                template = el
                break
            end
        end
    end

    if not template then
        Logging.warning("[RWE] BinaryOption template not found!")
        return nil
    end

    local row = template:clone(layout)
    row.id = nil

    local opt = row.elements[1]
    local lbl = row.elements[2]

    opt.id = id
    opt.target = nil
    if lbl then lbl.id = nil end

    if opt.toolTipText then opt.toolTipText = "" end
    if lbl and lbl.toolTipText then lbl.toolTipText = "" end

    opt.onClickCallback = function(newState, element)
        local isChecked = (newState == 2)
        callback(isChecked)
    end

    if lbl and lbl.setText then
        lbl:setText(getTextSafe(textId .. "_short"))
    end

    layout:addElement(row)

    if opt.setState then
        opt:setState(state and 2 or 1)
    end

    local tooltipText = getTextSafe(textId .. "_long")
    if opt.setToolTipText then opt:setToolTipText(tooltipText) end
    if lbl and lbl.setToolTipText then lbl:setToolTipText(tooltipText) end
    opt.toolTipText = tooltipText
    if lbl then lbl.toolTipText = tooltipText end

    return opt
end

function RWEUIHelper.createMultiOption(layout, id, textId, options, state, callback)
    local template = nil

    for _, el in ipairs(layout.elements) do
        if el.elements and #el.elements >= 2 then
            local firstChild = el.elements[1]
            if firstChild.id and string.find(firstChild.id, "^multi") then
                template = el
                break
            end
        end
    end

    if not template then
        Logging.warning("[RWE] MultiOption template not found!")
        return nil
    end

    local row = template:clone(layout)
    row.id = nil

    local opt = row.elements[1]
    local lbl = row.elements[2]

    opt.id = id
    opt.target = nil
    if lbl then lbl.id = nil end

    if opt.setTexts then
        opt:setTexts(options)
    end

    if opt.setState then
        opt:setState(state)
    end

    opt.onClickCallback = function(newState, element)
        callback(newState)
    end

    if lbl and lbl.setText then
        lbl:setText(getTextSafe(textId .. "_short"))
    end

    layout:addElement(row)

    local tooltipText = getTextSafe(textId .. "_long")
    if opt.setToolTipText then opt:setToolTipText(tooltipText) end
    if lbl and lbl.setToolTipText then lbl:setToolTipText(tooltipText) end
    opt.toolTipText = tooltipText
    if lbl then lbl.toolTipText = tooltipText end

    return opt
end
