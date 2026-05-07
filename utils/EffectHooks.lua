-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- EffectHooks — patches FS25 class methods to apply EVENT_STATE
-- flags as real gameplay modifiers.
--
-- Installed at file-load time.  Uses a global sentinel so the
-- file is idempotent even if the engine loads it twice.
-- =========================================================
-- Author: TisonK
-- =========================================================

-- Global sentinel: prevent double-patching.
if _G.RWE_EffectHooks_installed then
    Logging.info("[EffectHooks] Already installed, skipping")
    return
end
_G.RWE_EffectHooks_installed = true

-- =====================
-- ECONOMY MANAGER HOOK
-- Patches EconomyManager.getPricePerLiter to apply EVENT_STATE
-- price multipliers whenever the player sells goods.
--
-- FS25 signature: getPricePerLiter(fillTypeIndex, supplyDemandPressure, ...)
-- fillTypeIndex is captured so per-crop modifiers from RWEEconomicAPI can be applied.
-- =====================
if EconomyManager and EconomyManager.getPricePerLiter then
    local origGetPrice = EconomyManager.getPricePerLiter

    EconomyManager.getPricePerLiter = function(self, fillTypeIndex, ...)
        local price = origGetPrice(self, fillTypeIndex, ...)
        if type(price) ~= "number" or price <= 0 then return price end
        if not g_RandomWorldEvents then return price end

        local s = g_RandomWorldEvents.EVENT_STATE
        local mult = 1.0

        -- Economic modifiers
        if s.marketBonus then mult = mult * (1 + s.marketBonus) end
        if s.marketMalus then mult = mult * (1 - s.marketMalus) end
        if s.priceFixing  then mult = mult * (1 + s.priceFixing) end
        if s.exportBonus  then mult = mult * (1 + s.exportBonus) end
        if s.economicCrisis and s.economicCrisis.marketMalus then
            mult = mult * (1 - s.economicCrisis.marketMalus)
        end

        -- Field modifiers
        if s.yieldBonus     then mult = mult * (1 + s.yieldBonus)     end
        if s.yieldMalus     then mult = mult * (1 - s.yieldMalus)     end
        if s.harvestBonus   then mult = mult * (1 + s.harvestBonus)   end
        if s.harvestMalus   then mult = mult * (1 - s.harvestMalus)   end
        if s.fieldSaleBonus then mult = mult * (1 + s.fieldSaleBonus) end
        if s.fieldSaleMalus then mult = mult * (1 - s.fieldSaleMalus) end

        -- Special / wildlife
        if s.tradeBonus then mult = mult * (1 + s.tradeBonus) end

        -- Per-crop-type modifiers from RWEEconomicAPI:setPriceModifier().
        -- Entries are keyed by FillType index or string.  Expired entries are
        -- lazily pruned here to avoid a separate cleanup pass.
        if s.customPriceModifiers and fillTypeIndex ~= nil then
            local entry = s.customPriceModifiers[fillTypeIndex]
            if entry then
                if entry.expiresAt and g_currentMission and g_currentMission.time > entry.expiresAt then
                    -- Expired — prune and skip.
                    s.customPriceModifiers[fillTypeIndex] = nil
                else
                    mult = mult * entry.multiplier
                end
            end
        end

        if mult ~= 1.0 and g_RandomWorldEvents.debug and g_RandomWorldEvents.debug.enabled then
            Logging.info(string.format(
                "[EffectHooks] Price modifier: x%.3f (fillType=%s base €%.2f -> €%.2f)",
                mult, tostring(fillTypeIndex), price, price * mult))
        end

        return price * mult
    end

    Logging.info("[EffectHooks] EconomyManager.getPricePerLiter hooked")
else
    Logging.warning("[EffectHooks] EconomyManager.getPricePerLiter not found — price hooks disabled")
end

-- =====================
-- VEHICLE DAMAGE HOOK
-- Patches Vehicle.addDamageAmount to scale incoming damage
-- based on durability EVENT_STATE flags.
-- =====================
if Vehicle and Vehicle.addDamageAmount then
    local origAddDamage = Vehicle.addDamageAmount

    Vehicle.addDamageAmount = function(self, damage, ...)
        if type(damage) ~= "number" or damage <= 0 then
            return origAddDamage(self, damage, ...)
        end
        if not g_RandomWorldEvents then
            return origAddDamage(self, damage, ...)
        end

        local s = g_RandomWorldEvents.EVENT_STATE
        local scaledDamage = damage

        if s.durabilityBoost then
            scaledDamage = scaledDamage * math.max(0, 1 - s.durabilityBoost)
        elseif s.durabilityMalus then
            scaledDamage = scaledDamage * (1 + s.durabilityMalus)
        end

        return origAddDamage(self, scaledDamage, ...)
    end

    Logging.info("[EffectHooks] Vehicle.addDamageAmount hooked")
else
    Logging.info("[EffectHooks] Vehicle.addDamageAmount not available in this build — durability scaling disabled")
end

Logging.info("[EffectHooks] Module loaded successfully")
