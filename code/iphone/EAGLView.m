//
//  EAGLView.m
//  Doom
//
//  Created by Cass Everitt on 2/20/09.
//  Copyright Id Software 2009. All rights reserved.
//
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

#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>

#import "EAGLView.h"

#include "doomiphone.h"

#include <pthread.h>

EAGLView *eaglview;
EAGLContext *context;

// Used by hud.c to correct LiveContainer non-uniform scaling
float g_viewBoundsWidth = 0.0f;
float g_viewBoundsHeight = 0.0f;

@implementation EAGLView

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

float screenResolutionScale = 1.0f;

CAEAGLLayer *eaglLayer;

- (void) Initialize {

	eaglview = self;

#if !TARGET_OS_TV
    self.multipleTouchEnabled = true;
#endif

	if ( [[UIScreen mainScreen] respondsToSelector:@selector(scale)] &&
		[self respondsToSelector:@selector(setContentScaleFactor:)] ) {

        screenResolutionScale = [UIScreen mainScreen].scale;
		[self setContentScaleFactor:[UIScreen mainScreen].scale];
	}

	eaglLayer = (CAEAGLLayer *)self.layer;
	eaglLayer.opaque = YES;

	eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
									[NSNumber numberWithBool:NO],
									kEAGLDrawablePropertyRetainedBacking,
									kEAGLColorFormatRGB565,
									kEAGLDrawablePropertyColorFormat,
									nil];

	context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
	assert( context );

	if ( ![EAGLContext setCurrentContext:context]) {
		[self release];
		return;
	}

    glGenFramebuffersOES(1, &mViewFramebuffer);
    glGenRenderbuffersOES(1, &mViewRenderbuffer);

	glBindFramebufferOES(GL_FRAMEBUFFER_OES, mViewFramebuffer);
	glBindRenderbufferOES(GL_RENDERBUFFER_OES, mViewRenderbuffer);

    [context renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)self.layer];

    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, mViewRenderbuffer);

	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
	glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);

    displaywidth = backingWidth;
    displayheight = backingHeight;

    // Track UIView size for LiveContainer aspect correction
    g_viewBoundsWidth  = self.bounds.size.width;
    g_viewBoundsHeight = self.bounds.size.height;

    glGenRenderbuffersOES(1, &mDepthRenderbuffer);
    glBindRenderbufferOES(GL_RENDERBUFFER_OES, mDepthRenderbuffer);
    glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH_COMPONENT16_OES, backingWidth, backingHeight);
    glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER_OES, mDepthRenderbuffer);

    glBindRenderbufferOES(GL_RENDERBUFFER_OES, mViewRenderbuffer);
    glBindFramebufferOES(GL_FRAMEBUFFER_OES, mViewFramebuffer);

    if ( glCheckFramebufferStatusOES( GL_FRAMEBUFFER_OES ) != GL_FRAMEBUFFER_COMPLETE_OES ) {
        printf( "Failed to make complete framebuffer object %x", glCheckFramebufferStatusOES( GL_FRAMEBUFFER_OES ) );
		assert( 0 );
    }

    return;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    g_viewBoundsWidth  = self.bounds.size.width;
    g_viewBoundsHeight = self.bounds.size.height;
}

- (id) initWithCoder:(NSCoder *)aCoder{

    if(self = [super initWithCoder:aCoder] ) {
        [self Initialize];
    }

    return self;
}

- (id) initWithFrame:(CGRect)rect{
    if(self = [super initWithFrame:rect] ) {
        [self Initialize];
    }
    return self;
}

- (void) handleTouches:(UIEvent*)event {
	int touchCount = 0;
	static int previousTouchCount;
	static int touchRover;
	int	touchThisSequence[MAX_TOUCHES];

	memset( touchThisSequence, 0, sizeof( touchThisSequence ) );

	NSSet *theTouches = [event allTouches];

    for (UITouch *myTouch in theTouches)
    {
        CGPoint touchLocation = [myTouch locationInView:self];

        // Map view points → framebuffer pixels (works in LiveContainer and normal install)
        CGSize boundsSize = self.bounds.size;
        if (boundsSize.width > 0.0f && boundsSize.height > 0.0f) {
            touchLocation.x *= ((float)backingWidth  / (float)boundsSize.width);
            touchLocation.y *= ((float)backingHeight / (float)boundsSize.height);
        } else {
            touchLocation.x *= screenResolutionScale;
            touchLocation.y *= screenResolutionScale;
        }

		const int x = touchLocation.x;
		const int y = touchLocation.y;
		touchCount++;

		touch_t	*t2;

		int		minDist = 64 * 64;
		int		minIndex = -1;
		for ( int i = 0 ; i < MAX_TOUCHES ; i++ ) {
			t2 = &sysTouches[i];
			if ( !t2->down ) {
				continue;
			}
			int dist = ( t2->x - x ) * ( t2->x - x ) + ( t2->y - y ) * ( t2->y - y );
			if ( dist < minDist ) {
				minDist = dist;
				minIndex = i;
			}
		}
		if ( minIndex != -1 ) {
			sysTouches[minIndex].x = x;
			sysTouches[minIndex].y = y;
			if (myTouch.phase == UITouchPhaseEnded) {
				if ( sysTouches[minIndex].stateCount == 1 ) {
					sysTouches[minIndex].stateCount = -1;
				} else {
					sysTouches[minIndex].down = false;
					sysTouches[minIndex].stateCount = 1;
				}
			} else {
				if (myTouch.phase == UITouchPhaseBegan) {
					sysTouches[minIndex].stateCount = 1;
					sysTouches[minIndex].controlOwner = NULL;
				}
				sysTouches[minIndex].down = true;
			}
			touchThisSequence[minIndex] = true;
		} else {
			if ( myTouch.phase != UITouchPhaseBegan ) {
				printf( "Non-local touch wasn't a begin\n" );
			} else {
				int i, j;
				for ( j = 0 ; j < MAX_TOUCHES ; j++ ) {
					i = touchRover;
					t2 = &sysTouches[i];
					touchRover = ( touchRover + 1 ) % MAX_TOUCHES;
					if ( !t2->down ) {
						break;
					}
				}
				if ( j == MAX_TOUCHES ) {
					printf( "MAX_TOUCHES, clearing everything!\n" );
					memset( sysTouches, 0, sizeof( sysTouches ) );
					continue;
				}
				t2->x = x;
				t2->y = y;
				t2->down = true;
				t2->controlOwner = NULL;
				t2->stateCount = 1;

				touchThisSequence[i] = true;
			}
		}
    }
	for ( int i = 0 ; i < MAX_TOUCHES ; i++ ) {
		if ( sysTouches[i].down && !touchThisSequence[i] ) {
			printf( "clearing touch %i\n", i );
			sysTouches[i].down = false;
			sysTouches[i].stateCount = 0;
			touchCount--;
		}
	}

	if ( touchCount == 4 && previousTouchCount != 4 ) {
		touchCount = 0;

		if ( textField == nil ) {
			textField = [UITextField alloc];
			[textField initWithFrame:CGRectMake( 0, 0, 20, 20 ) ];
			[self addSubview:textField];
			[textField release];
			textField.hidden = true;
			textField.delegate = self;
			textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
			textField.autocorrectionType = UITextAutocorrectionTypeNo;
			[textField becomeFirstResponder];
		} else {
		}
	}

	previousTouchCount = touchCount;
}

- (void) touchesBegan:(NSSet*)touchSet withEvent:(UIEvent*)event {
	(void)touchSet;
	[self handleTouches:event];
}

- (void)touchesMoved:(NSSet *)touchSet withEvent:(UIEvent *)event {
	(void)touchSet;
	[self handleTouches:event];
}

- (void) touchesEnded:(NSSet*)touchSet withEvent:(UIEvent*)event {
	(void)touchSet;
	[self handleTouches:event];
}

- (void)touchesCancelled:(NSSet *)touchSet withEvent:(UIEvent *)event {
	(void)touchSet;
	[self handleTouches:event];
}

@end

@implementation EAGLView (UITextFieldDelegate)

char	consoleCommand[1024];

- (BOOL)textFieldShouldReturn:(UITextField *)_textField
{
	(void)_textField;

	if ( eaglview->textField == nil ) {
		return YES;
	}

	const char *line = [ eaglview->textField.text UTF8String ];
	strncpy( consoleCommand, line, sizeof(consoleCommand)-1 );
	eaglview->textField.text = [ NSString stringWithUTF8String: "" ];

	[textField resignFirstResponder];
	[textField removeFromSuperview];
	textField = nil;

	return YES;
}

@end

const char * SysIPhoneGetConsoleTextField() {
	if ( eaglview->textField == nil ) {
		return "";
	}
	return [ eaglview->textField.text UTF8String ];
}

void SysIPhoneSetConsoleTextField( const char * str) {
	assert( eaglview->textField != nil );
	eaglview->textField.text = [ NSString stringWithUTF8String: str ];
}

void SysIPhoneSwapBuffers() {

    glBindRenderbufferOES(GL_RENDERBUFFER_OES, eaglview->mViewRenderbuffer);
    [context presentRenderbuffer:GL_RENDERBUFFER_OES];

}