#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(ArchiveModule, NSObject)
RCT_EXTERN_METHOD(archiveSession:(NSString *)folderPath
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(previewSession:(NSString *)folderPath
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
@end
