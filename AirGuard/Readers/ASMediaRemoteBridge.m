#import "ASMediaRemoteBridge.h"
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>

typedef void (*MRGetNowPlayingInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetNowPlayingApplicationPIDFunction)(dispatch_queue_t, void (^)(pid_t));
typedef void (*MRRegisterNotificationsFunction)(dispatch_queue_t);
typedef BOOL (*MRSendCommandFunction)(NSInteger, NSDictionary *);

static NSString * const ASNowPlayingInfoDidChange = @"kMRMediaRemoteNowPlayingInfoDidChangeNotification";
static NSString * const ASNowPlayingPlaybackDidChange = @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification";
static NSString * const ASNowPlayingApplicationDidChange = @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification";

@implementation ASMediaRemoteBridge {
    void *_framework;
    MRGetNowPlayingInfoFunction _getNowPlayingInfo;
    MRGetNowPlayingApplicationPIDFunction _getNowPlayingApplicationPID;
    MRRegisterNotificationsFunction _registerNotifications;
    MRSendCommandFunction _sendCommand;
    BOOL _started;
}

- (BOOL)start {
    if (_started) { return YES; }

    _framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (_framework == NULL) { return NO; }

    _getNowPlayingInfo = (MRGetNowPlayingInfoFunction)dlsym(_framework, "MRMediaRemoteGetNowPlayingInfo");
    _getNowPlayingApplicationPID = (MRGetNowPlayingApplicationPIDFunction)dlsym(_framework, "MRMediaRemoteGetNowPlayingApplicationPID");
    _registerNotifications = (MRRegisterNotificationsFunction)dlsym(_framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
    _sendCommand = (MRSendCommandFunction)dlsym(_framework, "MRMediaRemoteSendCommand");
    if (_getNowPlayingInfo == NULL || _registerNotifications == NULL || _sendCommand == NULL) {
        dlclose(_framework);
        _framework = NULL;
        return NO;
    }

    _started = YES;
    _registerNotifications(dispatch_get_main_queue());

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(mediaRemoteChanged:) name:ASNowPlayingInfoDidChange object:nil];
    [center addObserver:self selector:@selector(mediaRemoteChanged:) name:ASNowPlayingPlaybackDidChange object:nil];
    [center addObserver:self selector:@selector(mediaRemoteChanged:) name:ASNowPlayingApplicationDidChange object:nil];
    [self refresh];
    return YES;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_framework != NULL) {
        dlclose(_framework);
    }
}

- (void)mediaRemoteChanged:(NSNotification *)notification {
    [self refresh];
}

- (void)refresh {
    [self refreshLegacyNowPlayingInfo];
}

- (void)refreshLegacyNowPlayingInfo {
    if (_getNowPlayingInfo == NULL) { return; }
    __weak typeof(self) weakSelf = self;
    _getNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        if (strongSelf->_getNowPlayingApplicationPID == NULL) {
            [strongSelf deliverInfo:info withProcessIdentifier:0];
            return;
        }
        strongSelf->_getNowPlayingApplicationPID(dispatch_get_main_queue(), ^(pid_t pid) {
            __strong typeof(weakSelf) nestedSelf = weakSelf;
            if (nestedSelf == nil) { return; }
            [nestedSelf deliverInfo:info withProcessIdentifier:pid];
        });
    });
}

- (void)deliverInfo:(NSDictionary *)info withProcessIdentifier:(pid_t)pid {
    if (pid > 0) {
        NSMutableDictionary *mergedInfo = [info mutableCopy] ?: [NSMutableDictionary dictionary];
        mergedInfo[@"processIdentifier"] = @(pid);
        info = mergedInfo;
    }
    ASNowPlayingInfoHandler handler = self.infoHandler;
    if (handler != nil) { handler(info); }
}

- (void)togglePlayPause { [self sendCommand:2]; }
- (void)nextTrack { [self sendCommand:4]; }
- (void)previousTrack { [self sendCommand:5]; }

- (void)sendCommand:(NSInteger)command {
    if (_sendCommand != NULL) {
        if (_sendCommand(command, nil)) { return; }
    }
    NSInteger mediaKey = command == 4 ? 17 : (command == 5 ? 18 : 16);
    [self postMediaKey:mediaKey];
}

- (void)postMediaKey:(NSInteger)key {
    for (NSNumber *isDown in @[@YES, @NO]) {
        NSInteger flags = isDown.boolValue ? 0xA00 : 0xB00;
        NSInteger data1 = (key << 16) | flags;
        NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                                            location:NSZeroPoint
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:0
                                             context:nil
                                             subtype:8
                                               data1:data1
                                               data2:-1];
        if (event.CGEvent != NULL) {
            CGEventPost(kCGHIDEventTap, event.CGEvent);
        }
    }
}

@end
