-- =========================================================
-- Random World Events (version 2.1.3.0) - FS25
-- =========================================================
-- EffectHooks: patches FS25 class methods to apply EVENT_STATE
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
-- PRICE PATH (EC-6)
-- The EconomyManager.getPricePerLiter patch that lived here is gone. Selling
-- stations price through SellingStation:getEffectiveFillTypePrice and never called
-- it; fill-trigger purchases, bale value and production payouts did. World-event
-- sell-price swings now reach selling points only through MarketDynamics'
-- registered consumer modifier (integrations/RWEMarketBridge.lua).
-- =====================

-- =====================
-- VEHICLE DAMAGE HOOK
-- Patches Vehicle.addDamageAmount to scale incoming damage based on the
-- durability EVENT_STATE flags. Redesign: this global patch only acts behind
-- the arcadePhysics opt-in toggle (default OFF), and even then only for the
-- player's own vehicle. When the toggle is OFF the patch is a transparent
-- pass-through so normal gameplay damage is never touched.
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
        if not g_RandomWorldEvents:allowsArcadePhysics() then
            return origAddDamage(self, damage, ...)
        end

        -- Never scale damage on an NPC-driven vehicle.
        local isPlayerVehicle = false
        local p = g_localPlayer
        if p ~= nil and p.getCurrentVehicle ~= nil then
            isPlayerVehicle = p:getCurrentVehicle() == self
        elseif g_currentMission ~= nil then
            isPlayerVehicle = g_currentMission.controlledVehicle == self
        end
        if not isPlayerVehicle then
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

    Logging.info("[EffectHooks] Vehicle.addDamageAmount hooked (arcade-physics gate)")
else
    Logging.info("[EffectHooks] Vehicle.addDamageAmount not available in this build — durability scaling disabled")
end

Logging.info("[EffectHooks] Module loaded successfully")
