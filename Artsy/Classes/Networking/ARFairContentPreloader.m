#import "ARFairContentPreloader.h"
#import <netinet/in.h>
#import <arpa/inet.h>

@interface ARFairContentPreloader () <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property (nonatomic, strong) NSNetServiceBrowser *serviceBrowser;
@property (nonatomic, strong) NSNetService *service;
@property (nonatomic, strong) NSURL *serviceURL;
@property (nonatomic, strong) NSDictionary *manifest;
@property (nonatomic, assign) BOOL isResolvingService;
@end

@implementation ARFairContentPreloader

+ (instancetype)contentPreloader;
{
  return [[self alloc] initWithServiceName:@"Artsy-FairEnough-Server"];
}

- (instancetype)initWithServiceName:(NSString *)serviceName;
{
   if ((self = [super init])) {
     _serviceName = [serviceName copy];
   }
   return self;
}

- (void)discoverFairService;
{
  self.isResolvingService = YES;
  self.serviceBrowser = [NSNetServiceBrowser new];
  self.serviceBrowser.delegate = self;
  [self.serviceBrowser searchForServicesOfType:@"_http._tcp" inDomain:@""];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreServicesComing;
{
  NSLog(@"SERVICE: %@ MORE: %@", service, @(moreServicesComing));
  if ([service.name isEqualToString:self.serviceName]) {
    self.service = service;
    if (service.addresses.count > 0) {
      [self resolveAddress];
    } else {
      self.service.delegate = self;
      [self.service resolveWithTimeout:10];
    }
    [self.serviceBrowser stop];
    return;
  }
  if (!moreServicesComing) {
    DDLogDebug(@"Unable to find a Artsy-FairEnough-Server Bonjour service.");
    [self.serviceBrowser stop];
    // TODO Tell delegate to release this object.
    self.isResolvingService = NO;
  }
}

- (void)netServiceDidResolveAddress:(NSNetService *)service;
{
  if (service.addresses.count > 0) {
    [service stop];
    [self resolveAddress];
  }
}

- (BOOL)hasResolvedService;
{
  return self.service.addresses.count > 0;
}

- (void)netServiceDidStop:(NSNetService *)service;
{
  self.isResolvingService = NO;
  if (!self.hasResolvedService) {
    NSLog(@"FAILED TO RESOLVE SERVICE!");
  }
}

- (void)resolveAddress;
{
  for (NSData *addressData in self.service.addresses) {
    const struct sockaddr *address = (const struct sockaddr *)addressData.bytes;
    // IPv4
    if (address->sa_family == AF_INET) {
      self.serviceURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://%s:%ld", inet_ntoa(((struct sockaddr_in *)address)->sin_addr), (long)self.service.port]];
      NSLog(@"Found IPv4 address: %@", self.serviceURL);
    } else if (address->sa_family == AF_INET6) {
      // TODO?
      // NSLog(@"Found IPv6 address");
    } else {
      NSLog(@"Unknown address type");
    }
  }
}

- (void)fetchManifest:(void(^)(NSError *))completionBlock;
{
  @weakify(self);
  NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:self.manifestURL
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    @strongify(self);
    if (!self) return;

    if (data) {
      NSError *jsonError = nil;
      self.manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
      if (self.manifest) {
        NSLog(@"MANIFEST: %@", self.manifest);
        completionBlock(nil);
      } else {
        NSLog(@"FAILED TO DESERIALIZE JSON: %@", jsonError);
        completionBlock(jsonError);
      }
    } else {
      NSLog(@"FAILED TO FETCH MANIFEST: %@", error);
      completionBlock(error);
    }
  }];
  [task resume];
}

- (NSURL *)manifestURL;
{
  return [self.serviceURL URLByAppendingPathComponent:@"/fair/manifest"];
}

- (NSString *)fairName;
{
  return self.manifest[@"fair"];
}

@end
