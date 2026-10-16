//
//  GameController.mm
//  doomengine
//
//  Created by John Watson on 1/29/15.
//  Updated for reliable connect/disconnect + basic/extended gamepad support.
//

/*
 
 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 
 */

#import <GameController/GameController.h>

#import "doomiphone.h"
#import "GameController.h"

static GCController *controller = nil;
static bool togglePause = false;
static bool observersRegistered = false;

// Edge detection so weapon / menu buttons fire once per press
static bool prevButtonX = false;
static bool prevButtonY = false;
static bool prevButtonMenu = false;

typedef enum {
    WEAPON_PREVIOUS = 0,
    WEAPON_NEXT = 1,
} weaponswitch_e;

static bool HasAmmo(int weaponType) {
    // Fist always available
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
    }

    return ammo > 0;
}

static int SwitchWeapon(weaponswitch_e direction) {
    int index = players[consoleplayer].readyweapon;

    if (direction == WEAPON_PREVIOUS) {
        do {
            if (--index < 0) {
                index = NUMWEAPONS - 1;
            }
        } while (!HasAmmo(index));
    } else {
        do {
            if (++index >= NUMWEAPONS) {
                index = 0;
            }
        } while (!HasAmmo(index));
    }

    return index;
}

static void PickBestController(void) {
    controller = nil;
    NSArray *controllers = [GCController controllers];
    for (GCController *c in controllers) {
        if (c.extendedGamepad || c.gamepad) {
            controller = c;
            break;
        }
    }
}

static void RegisterObserversIfNeeded(void) {
    if (observersRegistered) {
        return;
    }
    observersRegistered = true;

    // Pick whatever is already connected
    PickBestController();

    NSNotificationCenter *ns = [NSNotificationCenter defaultCenter];

    // Always register — even if no controller is present at launch
    [ns addObserverForName:GCControllerDidConnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        PickBestController();
    }];

    [ns addObserverForName:GCControllerDidDisconnectNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        PickBestController();
    }];
}

/**
 Returns true if a usable MFi / GameController pad is connected.
 Observers are registered on first call so hot-plug works.
 */
bool iphoneControllerIsAvailable(void) {
    RegisterObserversIfNeeded();
    return controller != nil;
}

void iphoneControllerInput(ticcmd_t *cmd) {
    if (!iphoneControllerIsAvailable() || !controller) {
        return;
    }

    GCExtendedGamepad *ext = controller.extendedGamepad;
    GCGamepad *basic = controller.gamepad;

    if (ext) {
        // Dual-stick + triggers (modern extended profile)
        cmd->angleturn   += (int)(ext.rightThumbstick.xAxis.value * -ROTATETHRESHOLD);
        cmd->forwardmove += (int)(ext.leftThumbstick.yAxis.value  *  TURBOTHRESHOLD);
        cmd->sidemove    += (int)(ext.leftThumbstick.xAxis.value  *  TURBOTHRESHOLD);

        // D-pad as movement fallback
        if (ext.dpad.up.pressed)    cmd->forwardmove += TURBOTHRESHOLD;
        if (ext.dpad.down.pressed)  cmd->forwardmove -= TURBOTHRESHOLD;
        if (ext.dpad.left.pressed)  cmd->sidemove    -= TURBOTHRESHOLD;
        if (ext.dpad.right.pressed) cmd->sidemove    += TURBOTHRESHOLD;

        if (ext.rightTrigger.pressed) {
            cmd->buttons |= BT_ATTACK;
        }
        if (ext.buttonA.pressed) {
            cmd->buttons |= BT_USE;
        }

        // Weapon switch (edge-triggered)
        bool xDown = ext.buttonX.pressed;
        bool yDown = ext.buttonY.pressed;

        if (xDown && !prevButtonX && players[consoleplayer].pendingweapon == wp_nochange) {
            int w = SwitchWeapon(WEAPON_PREVIOUS);
            if (w != players[consoleplayer].readyweapon) {
                cmd->buttons |= BT_CHANGE;
                cmd->buttons |= w << BT_WEAPONSHIFT;
            }
        }
        if (yDown && !prevButtonY && players[consoleplayer].pendingweapon == wp_nochange) {
            int w = SwitchWeapon(WEAPON_NEXT);
            if (w != players[consoleplayer].readyweapon) {
                cmd->buttons |= BT_CHANGE;
                cmd->buttons |= w << BT_WEAPONSHIFT;
            }
        }
        prevButtonX = xDown;
        prevButtonY = yDown;

        // Menu / pause
        bool menuDown = NO;
        if (@available(iOS 13.0, *)) {
            menuDown = ext.buttonMenu.pressed;
        }
        if (menuDown && !prevButtonMenu) {
            togglePause = true;
        }
        prevButtonMenu = menuDown;

    } else if (basic) {
        // Older basic gamepad profile
        if (basic.dpad.up.pressed)    cmd->forwardmove += TURBOTHRESHOLD;
        if (basic.dpad.down.pressed)  cmd->forwardmove -= TURBOTHRESHOLD;
        if (basic.dpad.left.pressed)  cmd->sidemove    -= TURBOTHRESHOLD;
        if (basic.dpad.right.pressed) cmd->sidemove    += TURBOTHRESHOLD;

        if (basic.buttonA.pressed) {
            cmd->buttons |= BT_USE;
        }
        if (basic.buttonB.pressed) {
            cmd->buttons |= BT_ATTACK;
        }

        bool xDown = basic.buttonX.pressed;
        bool yDown = basic.buttonY.pressed;

        if (xDown && !prevButtonX && players[consoleplayer].pendingweapon == wp_nochange) {
            int w = SwitchWeapon(WEAPON_PREVIOUS);
            if (w != players[consoleplayer].readyweapon) {
                cmd->buttons |= BT_CHANGE;
                cmd->buttons |= w << BT_WEAPONSHIFT;
            }
        }
        if (yDown && !prevButtonY && players[consoleplayer].pendingweapon == wp_nochange) {
            int w = SwitchWeapon(WEAPON_NEXT);
            if (w != players[consoleplayer].readyweapon) {
                cmd->buttons |= BT_CHANGE;
                cmd->buttons |= w << BT_WEAPONSHIFT;
            }
        }
        prevButtonX = xDown;
        prevButtonY = yDown;
    }

    if (togglePause) {
        cmd->buttons |= BT_SPECIAL | (BTS_PAUSE & BT_SPECIALMASK);
        togglePause = false;
    }
}