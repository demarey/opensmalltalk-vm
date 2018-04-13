//
//  sqSqueakOSXApplication+events.m
//  SqueakPureObjc
//
//  Created by John M McIntosh on 09-11-15.
/*
 Some of this code was funded via a grant from the European Smalltalk User Group (ESUG)
 Copyright 2009 Corporate Smalltalk Consulting Ltd. All rights reserved.
 MIT License
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 
 The end-user documentation included with the redistribution, if any, must include the following acknowledgment: 
 "This product includes software developed by Corporate Smalltalk Consulting Ltd (http://www.smalltalkconsulting.com) 
 and its contributors", in the same place and form as other third-party acknowledgments. 
 Alternately, this acknowledgment may appear in the software itself, in the same form and location as other 
 such third-party acknowledgments.
 */
//

#import "sqSqueakOSXApplication+events.h"
#import "SqueakOSXAppDelegate.h"
#import "sqSqueakOSXScreenAndWindow.h"
#import "sqMacV2Browser.h"
#import "sqSqueakOSXInfoPlistInterface.h"
#import "keyBoardStrokeDetails.h"
#import "sqMacHostWindow.h"

extern struct	VirtualMachine* interpreterProxy;
extern SqueakOSXAppDelegate *gDelegateApp;

static int buttonState=0;

@interface sqSqueakOSXApplication (eventsPrivate)

- (sqButton) resolveModifier:(sqModifier)modifier forMouseButton:(sqButton)mouseButton;

@end

@implementation sqSqueakOSXApplication (eventsPrivate)

- (sqButton) resolveModifier:(sqModifier)modifier forMouseButton:(sqButton)mouseButton {
    return (browserActiveAndDrawingContextOkAndNOTInFullScreenMode())
    ? [(sqSqueakOSXInfoPlistInterface *) self.infoPlistInterfaceLogic getSqueakBrowserMouseMappingsAt: modifier by: mouseButton]
    : [(sqSqueakOSXInfoPlistInterface *) self.infoPlistInterfaceLogic getSqueakMouseMappingsAt: modifier by: mouseButton];
}

@end

@implementation sqSqueakOSXApplication (events)

- (void) pumpRunLoopEventSendAndSignal:(BOOL)signal {
    NSEvent *event;
    
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:nil
                                          inMode:NSEventTrackingRunLoopMode
                                         dequeue:YES])) {
        [NSApp sendEvent: event];
        if (signal) {
            interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);
        }
    }
}

- (void) pumpRunLoop {	
    [super pumpRunLoop]; 
    [self pumpRunLoopEventSendAndSignal:NO];
	/* 
	 http://www.cocoabuilder.com/archive/cocoa/228473-receiving-user-events-from-within-an-nstimer-callback.html
	 The reason you have to do this and can't just run the runloop is
	 because the event loop is actually a separate concept from the
	 runloop. It's a bit confusing because the event loop is implemented
	 using the runloop, but if you just run the runloop on the main thread,
	 events won't get processed. You have to explicitly run this in order
	 to get them to be processed.
	 
	 Note that using the default runloop mode with this is generally a bad
	 idea. By running in the default mode you allow *everything* else to
	 run, which means that some other code might decide that *it* wants an
	 inner event loop as well. If you then want to quit before that other
	 code has finished, tough cookies. Much better to control things more
	 tightly by using a different runloop mode.
	 
	 */
	
}

- (void ) processAsOldEventOrComplexEvent: (id) event placeIn: (sqInputEvent *) evt {
	if ([event[0] intValue] == 1) {
		[(NSData *)event[1] getBytes: evt length: sizeof(sqInputEvent)];
		if (evt->type == EventTypeKeyboard) {
//			NSLog(@"keyboard pc %i cc %i uc %i m %i",((sqKeyboardEvent *)evt)->pressCode,((sqKeyboardEvent *) evt)->charCode,((sqKeyboardEvent *) evt)->utf32Code,((sqKeyboardEvent *) evt)->modifiers);
		}
		return;
	}
}

- (void) pushEventToQueue: (sqInputEvent *) evt {
	[eventQueue addItem: @[@1,[NSData  dataWithBytes:(const void *) evt length: sizeof(sqInputEvent)]]];
}

- (void) recordCharEvent:(NSString *) unicodeString fromView: (NSView <sqSqueakOSXView> *) mainView {
	sqKeyboardEvent evt;
	unichar unicode;
	unsigned char macRomanCharacter;
	NSInteger	i;
	NSRange picker;
	NSUInteger totaLength;
	
	evt.type = EventTypeKeyboard;
	evt.timeStamp =  ioMSecs();
	picker.location = 0;
	picker.length = 1;
	totaLength = [unicodeString length];

	for (i=0;i < totaLength;i++) {
		
		
		unicode = [unicodeString characterAtIndex: i];
		
		if (mainView.lastSeenKeyBoardStrokeDetails) {
			evt.modifiers = [self translateCocoaModifiersToSqueakModifiers: mainView.lastSeenKeyBoardStrokeDetails.modifierFlags];
			evt.charCode = mainView.lastSeenKeyBoardStrokeDetails.keyCode;
		} else {
			evt.modifiers = 0;
			evt.charCode = 0;
		}

		if ((evt.modifiers & CommandKeyBit) && (evt.modifiers & ShiftKeyBit)) {  /* command and shift */
			if ((unicode >= 97) && (unicode <= 122)) {
				/* convert ascii code of command-shift-letter to upper case */
				unicode = unicode - 32;
			}
		}
		
		NSString *lookupString = AUTORELEASEOBJ([[NSString alloc] initWithCharacters: &unicode length: 1]);
		[lookupString getBytes: &macRomanCharacter maxLength: 1 usedLength: NULL encoding: NSMacOSRomanStringEncoding
					   options: 0 range: picker remainingRange: NULL];
		
		evt.pressCode = EventKeyDown;
		unsigned short keyCodeRemembered = evt.charCode;
		evt.utf32Code = 0;
		evt.reserved1 = 0;
		evt.windowIndex =   mainView.windowLogic.windowIndex;
		[self pushEventToQueue: (sqInputEvent *)&evt];
		
		evt.charCode =	macRomanCharacter;
		evt.pressCode = EventKeyChar;
		evt.modifiers = evt.modifiers;		
		evt.utf32Code = unicode;
		
		[self pushEventToQueue: (sqInputEvent *) &evt];
		
		if (i > 1 || !mainView.lastSeenKeyBoardStrokeDetails) {
			evt.pressCode = EventKeyUp;
			evt.charCode = keyCodeRemembered;
			evt.utf32Code = 0;
			[self pushEventToQueue: (sqInputEvent *) &evt];
		}
	}
	
	interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);

}

- (void) recordKeyDownEvent:(NSEvent *)theEvent fromView: (NSView <sqSqueakOSXView> *) aView {
	sqKeyboardEvent evt;

	evt.type = EventTypeKeyboard;
	evt.timeStamp =  ioMSecs();
	evt.charCode =	[theEvent keyCode];
	evt.pressCode = EventKeyDown;
	evt.modifiers = [self translateCocoaModifiersToSqueakModifiers: [theEvent modifierFlags]];
	evt.utf32Code = 0;
	evt.reserved1 = 0;
	evt.windowIndex = [[aView windowLogic] windowIndex];
	[self pushEventToQueue: (sqInputEvent *) &evt];

	interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);
}

- (void) recordKeyUpEvent:(NSEvent *)theEvent fromView: (NSView <sqSqueakOSXView> *) aView {
	sqKeyboardEvent evt;

	evt.type = EventTypeKeyboard;
	evt.timeStamp =  ioMSecs();
	evt.charCode =	[theEvent keyCode];
	evt.pressCode = EventKeyUp;
	evt.modifiers = [self translateCocoaModifiersToSqueakModifiers: [theEvent modifierFlags]];
	evt.utf32Code = 0;
	evt.reserved1 = 0;
	evt.windowIndex =  aView.windowLogic.windowIndex;
	[self pushEventToQueue: (sqInputEvent *) &evt];

	interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);
}

- (void) recordMouseEvent:(NSEvent *)theEvent fromView: (NSView <sqSqueakOSXView> *) aView{
	sqMouseEvent evt;

	evt.type = EventTypeMouse;
	evt.timeStamp = ioMSecs();
	
	NSPoint local_point = [aView convertPoint: [theEvent locationInWindow] fromView:nil];
	
	evt.x =  lrintf((float)local_point.x);
	evt.y =  lrintf((float)local_point.y);
	
	int buttonAndModifiers = [self mapMouseAndModifierStateToSqueakBits: theEvent];
	evt.buttons = buttonAndModifiers & 0x07;
	evt.modifiers = buttonAndModifiers >> 3;
#if COGVM | STACKVM
	evt.nrClicks = 0;
#else
	evt.reserved1 = 0;
#endif 
	evt.windowIndex =  aView.windowLogic.windowIndex;
	
	[self pushEventToQueue:(sqInputEvent *) &evt];
    //NSLog(@"mouse hit x %i y %i buttons %i mods %i",evt.x,evt.y,evt.buttons,evt.modifiers);
	interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);
}
						   
- (void) recordWheelEvent:(NSEvent *) theEvent fromView: (NSView <sqSqueakOSXView> *) aView{
		
	[self recordMouseEvent: theEvent fromView: aView];
	CGFloat x = [theEvent deltaX];
	CGFloat y = [theEvent deltaY];

	if (x != 0.0f) {
		[self fakeMouseWheelKeyboardEventsKeyCode: (x < 0 ? 124 : 123) ascii: (x < 0 ? 29 : 28) windowIndex:   aView.windowLogic.windowIndex];
	}
	if (y != 0.0f) {
		[self fakeMouseWheelKeyboardEventsKeyCode: (y < 0 ? 125 : 126) ascii: (y < 0 ? 31 : 30) windowIndex:  aView.windowLogic.windowIndex];
	}
}
		  
- (void) fakeMouseWheelKeyboardEventsKeyCode: (int) keyCode ascii: (int) ascii windowIndex: (int) windowIndex {
	sqKeyboardEvent evt;

	evt.type = EventTypeKeyboard;
	evt.timeStamp = ioMSecs();
	evt.pressCode = EventKeyDown;
	evt.charCode = keyCode;
	evt.utf32Code = 0;
	evt.reserved1 = 0;
    evt.modifiers = (CtrlKeyBit | OptionKeyBit | CommandKeyBit | ShiftKeyBit);
	evt.windowIndex = windowIndex;
	[self pushEventToQueue:(sqInputEvent *) &evt];

	evt.pressCode = EventKeyChar;
	evt.charCode = ascii;
	evt.utf32Code = ascii;
	[self pushEventToQueue:(sqInputEvent *) &evt];
	
	evt.pressCode = EventKeyUp;
	evt.charCode =	keyCode;
	evt.utf32Code = 0;
	[self pushEventToQueue:(sqInputEvent *) &evt];
	
}

/*
 * Mapping Cocoa Modifiers to Squeak modifiers.
 *
 * Cocoa has the modifiers in its -[NSEvent modifiers] flags. However, those
 * are somewhere withing the flags, masked by NSEventModifierFlagDeviceIndependentFlagsMask,
 * end enumerated by (10.12+ terms):
 *      NSEventModifierFlagCapsLock
 *      NSEventModifierFlagShift
 *      NSEventModifierFlagControl
 *      NSEventModifierFlagOption
 *      NSEventModifierFlagCommand
 *
 * As of 10.1 this means:
 * modifiers= 2r00000000000000000000000000000000
 * ---------------------------------------------
 * mask     = 2r11111111111111110000000000000000
 *(Caps     = 2r00000000000000010000000000000000)
 * Shift    = 2r00000000000000100000000000000000
 * Control  = 2r00000000000001000000000000000000
 * Option   = 2r00000000000010000000000000000000
 * Command  = 2r00000000000100000000000000000000
 *
 * and Squeak knows
 *
 * modifiers= 2r0000
 * -----------------
 * Shfit    = 2r0001
 * Control  = 2r0010
 * Option   = 2r0100
 * Comand   = 2r1000
 *
 * While we could just shift and mask, let's be clean an just check.
 */
- (int) translateCocoaModifiersToSqueakModifiers: (NSUInteger) modifiers {
    return
        (modifiers & NSEventModifierFlagShift   ? ShiftKeyBit   : 0) |
        (modifiers & NSEventModifierFlagControl ? CtrlKeyBit    : 0) |
        (modifiers & NSEventModifierFlagOption  ? OptionKeyBit  : 0) |
        (modifiers & NSEventModifierFlagCommand ? CommandKeyBit : 0);

}


- (int) mapMouseAndModifierStateToSqueakBits: (NSEvent *) event {
	/* On a two- or three-button mouse, the left button is normally considered primary and the
	 right button secondary, 
	 but left-handed users can reverse these settings as a matter of preference. 
	 The middle button on a three-button mouse is always the tertiary button. '
	 
	 But mapping assumes 1,2,3  red, yellow, blue
	 */
	
    sqModifier modifier = kSqModifierNone;
    sqButton mappedButton = kSqNoButton;
	sqButton mouseButton = kSqNoButton;
    NSInteger stButtons = 0;
	static NSInteger buttonStateBits[4] = {0,0,0,0};

    NSEventModifierFlags flags = [event modifierFlags];
	NSEventType whatHappened = [event type];

    switch ([event type]) {
        case NSEventTypeMouseMoved:
        case NSEventTypeScrollWheel:
            // retain old state;
            stButtons = buttonState;
            mouseButton = kSqNoButton;
            break;
        case NSEventTypeLeftMouseUp:
        case NSEventTypeLeftMouseDown:
            mouseButton = kSqRedButton;
            break;
        case NSEventTypeRightMouseUp:
        case NSEventTypeRightMouseDown:
            mouseButton = kSqYellowButton;
            break;
        default:
            //buttonNumber seems to count from 0.
            mouseButton = [event buttonNumber] + 1;
            break;
    }

    if (mouseButton != kSqNoButton && mouseButton <= kSqButtonMax) {
        // ctrl trumps opt trumps cmd trumps no modifier.
        if (flags & NSEventModifierFlagCommand) modifier = kSqModifierCmd;
        if (flags & NSEventModifierFlagOption)  modifier = kSqModifierOpt;
        if (flags & NSEventModifierFlagControl) modifier = kSqModifierCtrl;

        mappedButton = [self resolveModifier: modifier forMouseButton: mouseButton];
        NSInteger buttonIsDown =
            (whatHappened == NSEventTypeLeftMouseUp ||
             whatHappened == NSEventTypeRightMouseUp ||
             whatHappened == NSEventTypeOtherMouseUp) ? 0 : 1;
        buttonStateBits[mappedButton] = buttonIsDown;
        if (buttonIsDown) {
            stButtons |= (mappedButton == kSqRedButton    ? RedButtonBit    : 0);
            stButtons |= (mappedButton == kSqYellowButton ? YellowButtonBit : 0);
            stButtons |= (mappedButton == kSqBlueButton   ? BlueButtonBit   : 0);
        }
    }

	// button state: low three bits are mouse buttons; next 8 bits are modifier bits
    buttonState = ([self translateCocoaModifiersToSqueakModifiers: flags] << 3) | (stButtons & 0x7);
	return buttonState;
}

- (void) recordDragEvent:(int)dragType numberOfFiles:(int)numFiles where:(NSPoint)point windowIndex:(sqInt)windowIndex view:(NSView *)aView
{
	sqDragDropFilesEvent evt;
	
    NSPoint local_point = [aView convertPoint:point fromView:nil];
    
	evt.type= EventTypeDragDropFiles;
	evt.timeStamp= ioMSecs();
	evt.dragType= dragType;
	evt.x = lrintf(local_point.x);
	evt.y = lrintf(local_point.y);
	evt.modifiers= (buttonState >> 3);
	evt.numFiles= numFiles;
	evt.windowIndex =  windowIndex;
	[self pushEventToQueue: (sqInputEvent *) &evt];
	
	interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);
}

- (void) recordWindowEvent: (int) windowType window: (NSWIndow *) window {
	sqWindowEvent evt;
	
	evt.type= EventTypeWindow;
	evt.timeStamp=  ioMSecs();
	evt.action= windowType;
	evt.value1 =  0;
	evt.value2 =  0;
	evt.value3 =  0;
	evt.value4 =  0;
	evt.windowIndex = windowIndexFromHandle((__bridge wHandleType)window);
	[self pushEventToQueue: (sqInputEvent *) &evt];
	
	interpreterProxy->signalSemaphoreWithIndex(gDelegateApp.squeakApplication.inputSemaphoreIndex);
}

@end
