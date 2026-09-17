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
-- Scales the usage damage the player's own vehicle takes, from the durability
-- EVENT_STATE flags. Redesign: it only acts behind the arcadePhysics opt-in toggle
-- (default OFF), and even then only for the player's own vehicle. When the toggle
-- is OFF the wrapper is a transparent pass-through, so normal gameplay damage is
-- never touched.
--
-- Where the damage is (decompiled FS25 scripts):
--   * Usage damage accrues on the server in Wearable:onUpdateTick as
--     self:setDamageAmount(spec.damage + self:updateDamageAmount(dt))
--     (vehicles/specializations/Wearable.lua:161-166). addDamageAmount, patched
--     here before as Vehicle.addDamageAmount (which never existed, so the patch
--     never installed), is only the gsVehicleAddDamage console command, a used
--     sale item's starting damage and the shop preview.
--   * updateDamageAmount is a registered per-vehicle function (Wearable.lua:47).
--     Vehicle:load copies the type's functions onto each instance
--     (vehicles/Vehicle.lua:486) and only then raises onLoad (:866); raised events
--     look the listener function up on the Wearable table at call time
--     (specialization/SpecializationUtil.lua:12). So an appended Wearable.onLoad
--     replaces each loaded vehicle's own updateDamageAmount, whenever the type's
--     function table was captured.
--   * Wearable:updateDebugValues (:366) calls the same function for the debug
--     readout, so while an event scales damage that readout shows the scaled rate.
-- =====================
local function rweScaleUsageDamage(self, damage)
    if type(damage) ~= "number" or damage <= 0 then
        return damage
    end
    if not g_RandomWorldEvents then
        return damage
    end
    if not g_RandomWorldEvents:allowsArcadePhysics() then
        return damage
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
        return damage
    end

    local s = g_RandomWorldEvents.EVENT_STATE
    local scaledDamage = damage

    if s.durabilityBoost then
        scaledDamage = scaledDamage * math.max(0, 1 - s.durabilityBoost)
    elseif s.durabilityMalus then
        scaledDamage = scaledDamage * (1 + s.durabilityMalus)
    end

    return scaledDamage
end

if Wearable ~= nil and type(Wearable.onLoad) == "function" then
    local origWearableOnLoad = Wearable.onLoad

    Wearable.onLoad = function(self, ...)
        origWearableOnLoad(self, ...)
        local ownUpdateDamage = self.updateDamageAmount
        if type(ownUpdateDamage) == "function" and not self.rweUsageDamageWrapped then
            self.rweUsageDamageWrapped = true
            self.updateDamageAmount = function(vehicle, dt, ...)
                return rweScaleUsageDamage(vehicle, ownUpdateDamage(vehicle, dt, ...))
            end
        end
    end

    Logging.info("[EffectHooks] Wearable.onLoad hooked: usage damage scaling installs per vehicle (arcade-physics gate)")
else
    Logging.info("[EffectHooks] Wearable.onLoad not available in this build; durability scaling disabled")
end

Logging.info("[EffectHooks] Module loaded successfully")
