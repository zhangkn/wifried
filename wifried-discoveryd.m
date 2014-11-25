/* WiFried - Fix for iOS 8.1 WiFi fix
 * Runs inside discoveryd to compensate for WiFiD2DPlugin issue
 *
 *   - Completely disable WiFi_D2D plugin (prevents AWDL/AirDrop/Peer 2 Peer WiFi (ie, GameKit)
 *
 * Copyright (C) 2014 @mariociabarra
*/

/* GNU Lesser General Public License, Version 3 {{{ */
/* This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
**/
/* }}} */

#include <CoreFoundation/CoreFoundation.h>
#include <Foundation/Foundation.h>
#undef __OSX_AVAILABLE_STARTING
#define __OSX_AVAILABLE_STARTING(x, y)
#include <SystemConfiguration/SystemConfiguration.h>

#include "substrate.h"
#include "WiFried.h"

struct WiFiManagerClient;
typedef struct WiFiManagerClient* WiFiManagerClientRef;

int WiFiManagerClientSetPower(WiFiManagerClientRef manager, bool on);
int WiFiManagerClientGetPower(WiFiManagerClientRef manager);
WiFiManagerClientRef WiFiManagerClientCreate(CFAllocatorRef allocator, int type);
 

// Prevents WiFiD2D From Loading
extern CFArrayRef CFBundleCreateBundlesFromDirectory( CFAllocatorRef allocator, CFURLRef directoryURL, CFStringRef bundleType);
CFArrayRef (*_CFBundleCreateBundlesFromDirectory)( CFAllocatorRef allocator, CFURLRef directoryURL, CFStringRef bundleType) = NULL;
CFArrayRef override_CFBundleCreateBundlesFromDirectory( CFAllocatorRef allocator, CFURLRef directoryURL, CFStringRef bundleType)
{

    CFArrayRef resultArray = _CFBundleCreateBundlesFromDirectory(allocator, directoryURL, bundleType);

    CFMutableArrayRef newArray = CFArrayCreateMutable(kCFAllocatorDefault, CFArrayGetCount(resultArray) - 1, &kCFTypeArrayCallBacks);
    for (int x =0; x < CFArrayGetCount(resultArray); x++)
    {
        CFBundleRef bundle = (CFBundleRef) CFArrayGetValueAtIndex(resultArray, x);
        CFURLRef bundleURL = CFBundleCopyBundleURL(bundle);
        if (bundleURL)
        {
            CFStringRef path = CFURLCopyPath(bundleURL);
            if (path)
            {
                if (CFStringCompare(path, CFSTR("/System/Library/PrivateFrameworks/DeviceToDeviceManager.framework/PlugIns/WiFiD2DPlugin.bundle/"), 0) != 0)
                    CFArrayAppendValue(newArray, bundle);
                else
                    NSLog(@"WiFried: Removed WiFiD2D Plugin from loading");
                CFRelease(path);
            }
            CFRelease(bundleURL);
        }
    }
    CFRelease(resultArray);
    resultArray = newArray;

    return resultArray;
}

void resetWiFi()
{
    static WiFiManagerClientRef wifiMan = nil;
    if (!wifiMan)
        wifiMan = WiFiManagerClientCreate(kCFAllocatorDefault, 0);

    if (wifiMan && WiFiManagerClientGetPower(wifiMan))
    {
        bool failed = false;
        if (WiFiManagerClientSetPower(wifiMan, false) != 0)
        {
            NSLog(@"WiFried: error bouncing wifi off!");
            failed = true;
        }
        if (WiFiManagerClientSetPower(wifiMan, true) != 0)
        {
            NSLog(@"WiFried: error bouncing wifi off!");
            failed = true;
        }
        if (!failed)
            NSLog(@"WiFried: Bounced WiFi");
    }
}

static void callback(SCDynamicStoreRef store, CFArrayRef changedKeys, void* info)
{
    NSLog(@"WiFried: Settings changed, resetting WiFi, exiting");
    resetWiFi();
    exit(0);
}

int getModeAndListenForChanges()
{
    int mode = 0;

    static SCDynamicStoreRef dynamicStore = nil;

    if (!dynamicStore)
    {
        dynamicStore = SCDynamicStoreCreate(kCFAllocatorDefault, CFSTR("wifried"), callback, NULL);
        if(!dynamicStore)
        {
            NSLog(@"WiFried: Could not open store, defaulting to bounce mode");
            return 0;
        }

        if(SCDynamicStoreSetDispatchQueue(dynamicStore, dispatch_get_main_queue()))
            SCDynamicStoreSetNotificationKeys(dynamicStore, (__bridge CFArrayRef)@[ SCWiFried_Key ], NULL);


        CFNumberRef cfMode = SCDynamicStoreCopyValue(dynamicStore, (CFStringRef)SCWiFried_Key);
        if (cfMode)
        {
            mode = [(__bridge NSNumber*)cfMode intValue];
            CFRelease(cfMode);
        }
    }

    return mode;
}

__attribute__((constructor)) static void initialize()
{
    NSLog(@"WiFried: Initializing WiFried");

    if(strcmp(getprogname(), "discoveryd") == 0)
    {
        int mode = getModeAndListenForChanges();
        if (mode == WIFID2D_COMPLETELY_OFF_MODE)
        {
            NSLog(@"WiFried: WiFiD2D Off Mode");
            resetWiFi();
            MSHookFunction(CFBundleCreateBundlesFromDirectory, override_CFBundleCreateBundlesFromDirectory, (void*) &_CFBundleCreateBundlesFromDirectory);
        }
        else
            NSLog(@"WiFried: Nothing Mode");
    }
}