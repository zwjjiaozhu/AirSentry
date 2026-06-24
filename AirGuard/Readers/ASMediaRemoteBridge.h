#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ASNowPlayingInfoHandler)(NSDictionary * _Nullable info);

@interface ASMediaRemoteBridge : NSObject

@property (nonatomic, copy, nullable) ASNowPlayingInfoHandler infoHandler;

- (BOOL)start;
- (void)refresh;
- (void)togglePlayPause;
- (void)nextTrack;
- (void)previousTrack;

@end

NS_ASSUME_NONNULL_END
