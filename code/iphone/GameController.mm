//
//  GameController.mm
//  doomengine
//
//  Updated for modern iOS / LiveContainer MFi support
//

#import <GameController/GameController.h>

#import "doomiphone.h"
#import "GameController.h"

static GCController *controller = nil;
static bool observersRegistered = false;

// Edge-detect state so buttons fire once per press
static bool prevMenuPressed = false;
static bool prevButtonXPressed = false;
static bool prevButtonYPressed = false;
static bool prevLeftShoulderPressed = false;
static bool prevRightShoulderPressed = false;

typedef enum {
    WEAPON_PREVIOUS = 0,
    WEAPON_NEXT = 1,
} weaponswitch_e;

static bool HasAmmo(int weaponType) {
    if (weaponType == wp_fist) {
        return true;
    }

    player_t *player = &players[consoleplayer];

    if (!player->weaponowned[weaponType]) {
        return false;
    }

    int ammo = -1;

    switch (weaponType) {
        case wp_pistol:       ammo = player->ammo[am_clip]; break;
        case wp_shotgun:      ammo = player->ammo[am_shell]; break;
        case wp_chaingun:     ammo = player->ammo[am_clip]; break;
        case wp_missile:      ammo = player->ammo[am_misl]; break;
        case wp_plasma:       ammo = player->ammo[am_cell]; break;
        case wp_bfg:          ammo = player->ammo[am_cell]; if (ammo < 40) ammo = 0; break;
        case wp_supershotgun: ammo = player->ammo[am_shell]; if (ammo < 2) ammo = 0; break;
        default: break;
    }

    return ammo > 0;
}

static int SwitchWeapon(weaponswitch_e direction) {
    int index = players[consoleplayer].readyweapon;

    if (direction == WEAPON_PREVIOUS) {
        --index;
        while (!HasAmmo(index)) {
            if (--index < 0) {
                index = NUMWEAPONS - 1;
            }
        }
    } else if (direction == WEAPON_NEXT) {
        ++index;
        while (!HasAmmo(index)) {
            if (++index >= NUMWEAPONS) {
                index = 0;
            }
        }
    }

    if (index == players[consoleplayer].readyweapon) {
        return wp_nochange;
    }

    return index;
}

static GCController *PickBestController(void) {
    NSArray *controllers = [GCController controllers];
    GCController *best = nil;

    for (GCController *c in controllers) {
        // Prefer extended gamepad (thumbsticks + triggers)
        if (c.extendedGamepad) {
            return c;
        }
        // Fall back to basic gamepad profile
        if (c.gamepad) {
            best = c;
        }
    }
    return best;
}

static void SelectController(GCController *c) {
    controller = c;
    // Reset edge-detect state on connect/disconnect
    prevMenuPressed = false;
    prevButtonXPressed = false;
    prevButtonYPressed = false;
    prevLeftShoulderPressed = false;
    prevRightShoulderPressed = false;
}

/**
 Lazily initialize game controller support.
 Always registers connect/disconnect observers so hot-plug works.
 */
bool iphoneControllerIsAvailable(void) {
    if (!observersRegistered) {
        observersRegistered = true;

        // Pick any controller already present
        SelectController(PickBestController());

#if !TARGET_OS_TV
        NSNotificationCenter *ns = [NSNotificationCenter defaultCenter];

        [ns addObserverForName:GCControllerDidConnectNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            // Prefer the newly connected controller if we have none,
            // or if the new one has a better profile.
            GCController *best = PickBestController();
            if (best != controller) {
                SelectController(best);
            }
        }];

        [ns addObserverForName:GCControllerDidDisconnectNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            // Re-pick from whatever is still connected
            SelectController(PickBestController());
        }];
#endif
    }

    // Also re-check in case LiveContainer / system state changed
    if (!controller) {
        SelectController(PickBestController());
    }

    return controller != nil;
}

void iphoneControllerInput(ticcmd_t *cmd) {
    if (!iphoneControllerIsAvailable()) {
        return;
    }

    GCExtendedGamepad *ext = controller.extendedGamepad;
    GCGamepad *basic = controller.gamepad;

    // ------------------------------------------------------------------
    // Movement / look
    // ------------------------------------------------------------------
    if (ext) {
        // Dual analog
        float turn   = ext.rightThumbstick.xAxis.value;
        float forward = ext.leftThumbstick.yAxis.value;
        float side   = ext.leftThumbstick.xAxis.value;

        // Optional: also allow D-pad as digital movement
        if (ext.dpad.up.pressed)    forward =  1.0f;
        if (ext.dpad.down.pressed)  forward = -1.0f;
        if (ext.dpad.left.pressed)  side    = -1.0f;
        if (ext.dpad.right.pressed) side    =  1.0f;

        cmd->angleturn   += (int)(turn * -ROTATETHRESHOLD);
        cmd->forwardmove += (int)(forward * TURBOTHRESHOLD);
        cmd->sidemove    += (int)(side * TURBOTHRESHOLD);

        // Fire
        if (ext.rightTrigger.pressed || ext.buttonB.pressed) {
            cmd->buttons |= BT_ATTACK;
        }

        // Use / open
        if (ext.buttonA.pressed) {
            cmd->buttons |= BT_USE;
        }

        // Weapon prev / next (edge-triggered)
        bool xPressed = ext.buttonX.pressed;
        bool yPressed = ext.buttonY.pressed;
        bool lsPressed = ext.leftShoulder.pressed;
        bool rsPressed = ext.rightShoulder.pressed;

        int newWeapon = wp_nochange;

        if ((xPressed && !prevButtonXPressed) || (lsPressed && !prevLeftShoulderPressed)) {
            if (players[consoleplayer].pendingweapon == wp_nochange) {
                newWeapon = SwitchWeapon(WEAPON_PREVIOUS);
            }
        }
        if ((yPressed && !prevButtonYPressed) || (rsPressed && !prevRightShoulderPressed)) {
            if (players[consoleplayer].pendingweapon == wp_nochange) {
                newWeapon = SwitchWeapon(WEAPON_NEXT);
            }
        }

        prevButtonXPressed = xPressed;
        prevButtonYPressed = yPressed;
        prevLeftShoulderPressed = lsPressed;
        prevRightShoulderPressed = rsPressed;

        if (newWeapon != wp_nochange) {
            cmd->buttons |= BT_CHANGE;
            cmd->buttons |= newWeapon << BT_WEAPONSHIFT;
        }

        // Pause via Menu button (replaces deprecated controllerPausedHandler)
        bool menuPressed = false;
        if (@available(iOS 13.0, *)) {
            if (ext.buttonMenu) {
                menuPressed = ext.buttonMenu.pressed;
            }
        }
        if (menuPressed && !prevMenuPressed) {
            cmd->buttons |= BT_SPECIAL | (BTS_PAUSE & BT_SPECIALMASK);
        }
        prevMenuPressed = menuPressed;

    } else if (basic) {
        // Basic gamepad profile (D-pad + face buttons + shoulders)
        float forward = 0.0f;
        float side = 0.0f;
        float turn = 0.0f;

        if (basic.dpad.up.pressed)    forward =  1.0f;
        if (basic.dpad.down.pressed)  forward = -1.0f;
        if (basic.dpad.left.pressed)  turn    = -1.0f;  // or side if you prefer strafe
        if (basic.dpad.right.pressed) turn    =  1.0f;

        cmd->angleturn   += (int)(turn * -ROTATETHRESHOLD);
        cmd->forwardmove += (int)(forward * TURBOTHRESHOLD);
        cmd->sidemove    += (int)(side * TURBOTHRESHOLD);

        if (basic.buttonB.pressed || basic.rightShoulder.pressed) {
            cmd->buttons |= BT_ATTACK;
        }
        if (basic.buttonA.pressed) {
            cmd->buttons |= BT_USE;
        }

        bool xPressed = basic.buttonX.pressed;
        bool yPressed = basic.buttonY.pressed;

        int newWeapon = wp_nochange;
        if (xPressed && !prevButtonXPressed &&
            players[consoleplayer].pendingweapon == wp_nochange) {
            newWeapon = SwitchWeapon(WEAPON_PREVIOUS);
        }
        if (yPressed && !prevButtonYPressed &&
            players[consoleplayer].pendingweapon == wp_nochange) {
            newWeapon = SwitchWeapon(WEAPON_NEXT);
        }
        prevButtonXPressed = xPressed;
        prevButtonYPressed = yPressed;

        if (newWeapon != wp_nochange) {
            cmd->buttons |= BT_CHANGE;
            cmd->buttons |= newWeapon << BT_WEAPONSHIFT;
        }
    }
}