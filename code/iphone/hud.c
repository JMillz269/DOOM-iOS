/*

 Copyright (C) 2009 Id Software, Inc.

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

#include "doomiphone.h"
#include "TargetConditionals.h"
#include <math.h>
#include "GameController.h"

hud_t	huds;

void HudDraw(void);
void HudWrite(void);
void HudRead(void);

ibutton_t	*dragHud;
int			dragX, dragY;

void SetHudPic( ibutton_t *hp, const char *image ) {
	pkTexture_t *gl;
	gl = PK_FindTexture( image );
	assert( gl );
	hp->texture = gl;
	hp->touch = NULL;
}

void SetHudSpot( ibutton_t *hp, int x, int y, int dw, int dh ) {
	hp->touch = NULL;

	float scaleX = (float)displaywidth  / 480.0f;
	float scaleY = (float)displayheight / 320.0f;
	float scale = (scaleX < scaleY) ? scaleX : scaleY;

	if (scale > 2.5f) scale = 2.5f;
	if (scale < 1.0f) scale = 1.0f;

	float sdw = dw * scale;
	float sdh = dh * scale;

	/*
	 * LiveContainer often presents the GL layer with a different aspect
	 * than the framebuffer. Squares then look like ovals.
	 * Compensate so controls stay circular after the container stretches.
	 */
	if (g_viewBoundsWidth > 1.0f && g_viewBoundsHeight > 1.0f &&
	    displaywidth > 0 && displayheight > 0) {
		float bufferAspect = (float)displaywidth / (float)displayheight;
		float viewAspect   = g_viewBoundsWidth / g_viewBoundsHeight;
		if (viewAspect > 0.01f) {
			float xStretch = viewAspect / bufferAspect;
			if (xStretch > 0.01f) {
				sdw = sdw / xStretch;
			}
		}
	}

	float sx = ((float)x / 480.0f) * (float)displaywidth;
	float sy = ((float)y / 320.0f) * (float)displayheight;

	hp->x = (int)(sx - sdw * 0.5f);
	hp->y = (int)(sy - sdh * 0.5f);
	hp->drawWidth  = (int)sdw;
	hp->drawHeight = (int)sdh;
	hp->buttonFlags = 0;
	hp->scale = 1.0f;
}

void HudSetTexnums() {
	SetHudPic( &huds.forwardStick, "iphone/up_down.tga" );
	SetHudPic( &huds.sideStick, "iphone/side_2_side.tga" );
	SetHudPic( &huds.turnStick, "iphone/directional_2.tga" );
	SetHudPic( &huds.turnRotor, "iphone/rotate.tga" );
	SetHudPic( &huds.fire, "iphone/fire.tga" );
	SetHudPic( &huds.menu, "iphone/menu_button.tga" );
	SetHudPic( &huds.map, "iphone/map_button.tga" );

	SetHudSpot( &huds.weaponSelect, 240, 280, 40, 40 );
}

void HudSetForScheme( int schemeNum ) {
	for ( ibutton_t *hud = (ibutton_t *)&huds ; hud != (ibutton_t *)(&huds+1) ; hud++ ) {
		hud->buttonFlags = BF_IGNORE;
	}
	int STICK_SIZE = 128;
	int HALF_STICK = 128/2;

	static const int BOTTOM = 320 - 44;
	SetHudSpot( &huds.weaponSelect, 240, 280, 40, 40 );

	switch ( schemeNum ) {
		default:
		case 0:
			SetHudSpot( &huds.forwardStick, HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.turnStick, HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.fire, 480-40, BOTTOM-HALF_STICK, 80, 80 );
			SetHudSpot( &huds.menu, 480-24, 24, 48, 48 );
			SetHudSpot( &huds.map, 24, 24, 48, 48 );
			break;
		case 1:
			SetHudSpot( &huds.forwardStick, HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.sideStick, HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.turnStick, 480-HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.fire, 480-40, 40, 80, 80 );
			SetHudSpot( &huds.menu, 48+24, 24, 48, 48 );
			SetHudSpot( &huds.map, 24, 24, 48, 48 );
			break;
		case 2:
			SetHudSpot( &huds.forwardStick, HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.sideStick, HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.turnRotor, 480-HALF_STICK, BOTTOM-HALF_STICK, STICK_SIZE, STICK_SIZE );
			SetHudSpot( &huds.fire, 480-40, 40, 80, 80 );
			SetHudSpot( &huds.menu, 48+24, 24, 48, 48 );
			SetHudSpot( &huds.map, 24, 24, 48, 48 );
			break;
	}

	huds.menu.buttonFlags |= BF_HUDBUTTON;
	huds.map.buttonFlags |= BF_HUDBUTTON;
	huds.fire.buttonFlags |= BF_SMALL_CLICK;
}

void SnapSticks( ibutton_t *test, const ibutton_t *to ) {
	if ( abs( test->x - to->x ) < test->drawWidth && abs( test->y - to->y ) < test->drawHeight ) {
		test->x = to->x;
		test->y = to->y;
	}
}

void HudUpdateControllerVisibility(void) {
	static int lastState = -1;
	int now = iphoneControllerIsAvailable() ? 1 : 0;

	if (now == lastState) {
		return;
	}
	lastState = now;

	if (now) {
		huds.forwardStick.buttonFlags |= BF_IGNORE;
		huds.sideStick.buttonFlags    |= BF_IGNORE;
		huds.turnStick.buttonFlags    |= BF_IGNORE;
		huds.turnRotor.buttonFlags    |= BF_IGNORE;
		huds.fire.buttonFlags         |= BF_IGNORE;
		huds.weaponSelect.buttonFlags |= BF_IGNORE;
	} else {
		huds.forwardStick.buttonFlags &= ~BF_IGNORE;
		huds.sideStick.buttonFlags    &= ~BF_IGNORE;
		huds.turnStick.buttonFlags    &= ~BF_IGNORE;
		huds.turnRotor.buttonFlags    &= ~BF_IGNORE;
		huds.fire.buttonFlags         &= ~BF_IGNORE;
		huds.weaponSelect.buttonFlags &= ~BF_IGNORE;

		extern cvar_t *controlScheme;
		int scheme = controlScheme ? (int)controlScheme->value : 0;
		HudSetForScheme(scheme);
	}
}

void HudEditFrame() {
	color3_t gray = { 32, 32, 32 };

	if ( numTouches == 0 && numPrevTouches == 1 && dragHud ) {
		Sound_StartLocalSound( "iphone/baction_01.wav" );
		dragHud = NULL;
	}

	if ( numTouches == 1 && numPrevTouches == 0 ) {
		int x = touches[0][0];
		int y = touches[0][1];
		dragHud = NULL;
		for ( ibutton_t *hud = (ibutton_t *)&huds ; hud != (ibutton_t *)(&huds+1) ; hud++ ) {
			if ( hud->buttonFlags & BF_IGNORE ) {
				continue;
			}
			if ( x >= hud->x && x - hud->x < hud->drawWidth && y >= hud->y && y - hud->y < hud->drawHeight ) {
				dragHud = hud;
				dragX = dragHud->x - x;
				dragY = dragHud->y - y;
				Sound_StartLocalSound( "iphone/bdown_01.wav" );
				break;
			}
		}
	}

	if ( numTouches == 1 && numPrevTouches == 1 && dragHud ) {
		dragHud->x = touches[0][0] + dragX;
		dragHud->y = touches[0][1] + dragY;
		if ( dragHud->x < 0 ) {
			dragHud->x = 0;
		}
		if ( dragHud->x > displaywidth - dragHud->drawWidth ) {
			dragHud->x = displaywidth - dragHud->drawWidth;
		}
		if ( dragHud->y < 0 ) {
			dragHud->y = 0;
		}
		if ( dragHud->y > displayheight - dragHud->drawHeight ) {
			dragHud->y = displayheight - dragHud->drawHeight;
		}

		if ( controlScheme->value == 0 ) {
			if ( dragHud == &huds.forwardStick ) {
				SnapSticks( &huds.turnStick, dragHud );
			}
		} else {
			if ( dragHud == &huds.forwardStick ) {
				SnapSticks( &huds.sideStick, dragHud );
			}
		}
	}

	R_Draw_Fill( 0, 0, 480, 320, gray );
	glColor4f( 1, 1, 1, 1 );
	iphoneCenterText( 240, 20, 0.75, "Drag the controls" );

	extern patchnum_t stbarbg;
	if ( statusBar->value ) {
		last_gltexture = NULL;
		gld_DrawNumPatch(0, ST_Y, stbarbg.lumpnum, CR_DEFAULT, VPT_STRETCH);
	}

	for ( ibutton_t *hud = (ibutton_t *)&huds ; hud != (ibutton_t *)(&huds+1) ; hud++ ) {
		if ( !hud->texture ) {
			continue;
		}
		if ( hud->buttonFlags & BF_IGNORE ) {
			continue;
		}

		PK_StretchTexture( hud->texture, hud->x, hud->y, hud->drawWidth, hud->drawHeight );
	}

	static ibutton_t btnDone;
	if ( !btnDone.texture ) {
		SetButtonPicsAndSizes( &btnDone, "iphone/back_button.tga", "Done", 240 - 32, 160-32, 64, 64 );
	}
	if ( HandleButton( &btnDone ) ) {
		menuState = IPM_MAIN;
        iphonePopGL();
	}
}