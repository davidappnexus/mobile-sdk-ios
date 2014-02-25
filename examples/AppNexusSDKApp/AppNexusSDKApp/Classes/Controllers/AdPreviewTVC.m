/*   Copyright 2013 APPNEXUS INC
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "AdPreviewTVC.h"
#import "AdSettings.h"
#import "ANBannerAdView.h"
#import "ANInterstitialAd.h"
#import "ANLogging.h"
#import "ANAdProtocol.h"
#import "AppNexusSDKAppGlobal.h"

#define SV_BACKGROUND_COLOR_RED 249.0
#define SV_BACKGROUND_COLOR_BLUE 249.0
#define SV_BACKGROUND_COLOR_GREEN 249.0
#define SV_BACKGROUND_COLOR_ALPHA 1.0 // On a scale from 0 -> 1

NSString *const kAppNexusSDKAppErrorTitle = @"Failed To Load Ad";
NSString *const kAppNexusSDKAppErrorCancel = @"OK";

@interface AdPreviewTVC () <ANInterstitialAdDelegate, ANBannerAdViewDelegate, UIScrollViewDelegate>

@property (strong, nonatomic) ANBannerAdView *bannerAdView;
@property (strong, nonatomic) ANInterstitialAd *interstitialAd;
@property (strong, nonatomic) UIButton *loadInterstitialButton;

@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UITableViewCell *scrollViewCell;

@end

@implementation AdPreviewTVC

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setup];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.bannerAdView.rootViewController = self;
}

- (void)setup {
    [self.refreshControl addTarget:self action:@selector(reloadAd) forControlEvents:UIControlEventValueChanged];
    self.scrollView.backgroundColor = [UIColor colorWithRed:SV_BACKGROUND_COLOR_RED/255.0
                                                      green:SV_BACKGROUND_COLOR_GREEN/255.0
                                                       blue:SV_BACKGROUND_COLOR_BLUE/255.0
                                                      alpha:SV_BACKGROUND_COLOR_ALPHA];
    [self loadAd];
}

- (void)loadAd {
    [self.refreshControl beginRefreshing];
    AdSettings *settings = [[AdSettings alloc] init];
    [self clearBannerAdView];
    [self clearInterstitialAd];

    if (settings.adType == AD_TYPE_BANNER) {
        ANLogDebug(@"%@ %@ | loading banner", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
        [self loadBannerAdWithSettings:settings];
    } else if (settings.adType == AD_TYPE_INTERSTITIAL) {
        ANLogDebug(@"%@ %@ | loading interstitial", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
        [self loadInterstitialAdWithSettings:settings];
    }
}

- (void)reloadAd {
    [self loadAd];
    [self.tableView reloadData];
}

- (void)loadAdvancedSettingsOnAdView:(ANAdView *)adView withSettings:(AdSettings *)settings {
    BOOL allowPSA = settings.allowPSA;
    BOOL opensInNativeBrowser = (settings.browserType == BROWSER_TYPE_DEVICE);
    NSString *age = settings.age;
    NSInteger gender = settings.gender;
    double reserve = settings.reserve;

    adView.shouldServePublicServiceAnnouncements = allowPSA;
    adView.opensInNativeBrowser = opensInNativeBrowser;
    
    if ([age length]) {
        adView.age = age;
    }
    if (gender != UNKNOWN) {
        adView.gender = gender;
    }
    if (reserve) {
        adView.reserve = reserve;
    }
    
    if (self.lastLocation) {
        [self.bannerAdView setLocationWithLatitude:self.lastLocation.coordinate.latitude
                                         longitude:self.lastLocation.coordinate.longitude
                                         timestamp:self.lastLocation.timestamp
                                horizontalAccuracy:self.lastLocation.horizontalAccuracy];
    }
    
    NSDictionary *customKeywords = settings.customKeywords;
    adView.customKeywords = [customKeywords mutableCopy];
    
    if ([settings.zipcode length]) {
        [adView.customKeywords setValue:settings.zipcode forKey:@"pcode"];
    }
}

- (void)loadBannerAdWithSettings:(AdSettings *)settings {
    CGFloat settingsBannerWidth = (CGFloat)settings.bannerWidth;
    CGFloat settingsBannerHeight = (CGFloat)settings.bannerHeight;
    NSString *settingsPlacementID = [NSString stringWithFormat:@"%d", settings.placementID];
    CGFloat settingsAutoRefreshInterval = (CGFloat)settings.refreshRate;
    
    CGFloat centerX = 0.0;
    CGFloat centerY = 0.0;
    if (settingsBannerWidth < self.tableView.frame.size.width) {
        centerX = (self.tableView.frame.size.width / 2.0) - (settingsBannerWidth / 2.0);
    }
    
    if (settingsBannerHeight < self.tableView.frame.size.height) {
        centerY = (self.tableView.frame.size.height / 2.0) - (settingsBannerHeight / 2.0);
    }
    
    [self clearBannerAdView];
    
    self.bannerAdView = [[ANBannerAdView alloc] initWithFrame:CGRectMake(centerX, centerY, settingsBannerWidth, settingsBannerHeight)];
    self.bannerAdView.delegate = self;
    self.bannerAdView.rootViewController = self;
    self.bannerAdView.adSize = CGSizeMake(settingsBannerWidth, settingsBannerHeight);
    self.bannerAdView.placementId = settingsPlacementID;
    [self loadAdvancedSettingsOnAdView:self.bannerAdView withSettings:settings];
    
    [self.bannerAdView setAutoRefreshInterval:settingsAutoRefreshInterval];
    [self.scrollView addSubview:self.bannerAdView];
    
    if(!settingsAutoRefreshInterval) { // If there's no refresh rate, then manually load one ad
        ANLogDebug(@"%@ %@ | no refresh rate, manually loading ad", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
        [self.bannerAdView loadAd];
    }
}

- (void)loadInterstitialAdWithSettings:(AdSettings *)settings {
    NSString *settingsPlacementID = [NSString stringWithFormat:@"%d", settings.placementID];
    NSString *backgroundColor = settings.backgroundColor;

    [self clearInterstitialAd];
    
    self.interstitialAd = [[ANInterstitialAd alloc] initWithPlacementId:settingsPlacementID];
    self.interstitialAd.delegate = self;
    self.interstitialAd.backgroundColor = [AppNexusSDKAppGlobal colorFromString:backgroundColor];
    [self loadAdvancedSettingsOnAdView:self.interstitialAd withSettings:settings];
    
    [self setupLoadInterstitialButton];
    
    [self.interstitialAd loadAd];
}

- (void)setupLoadInterstitialButton {
    self.loadInterstitialButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat borderWidth = 1.0;
    CGFloat cornerRadius = 2.0;
    [self.loadInterstitialButton.layer setCornerRadius:cornerRadius];
    [self.loadInterstitialButton.layer setBorderWidth:borderWidth];
    [self.loadInterstitialButton setHidden:YES];
    [self.loadInterstitialButton addTarget:self action:@selector(loadInterstitial:) forControlEvents:UIControlEventTouchDown];
    [self.loadInterstitialButton setTitle:@"Show Interstitial" forState:UIControlStateNormal];
    UIView *anchorView = self.scrollViewCell;
    [anchorView addSubview:self.loadInterstitialButton];
    NSLayoutConstraint *constraint1 = [NSLayoutConstraint constraintWithItem:self.loadInterstitialButton
                                                                   attribute:NSLayoutAttributeWidth
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:nil
                                                                   attribute:NSLayoutAttributeNotAnAttribute
                                                                  multiplier:1.0
                                                                    constant:(int)(self.loadInterstitialButton.intrinsicContentSize.width) + 2 * borderWidth + 4];
    NSLayoutConstraint *constraint2 = [NSLayoutConstraint constraintWithItem:self.loadInterstitialButton
                                                                   attribute:NSLayoutAttributeCenterX
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:anchorView
                                                                   attribute:NSLayoutAttributeCenterX
                                                                  multiplier:1.0
                                                                    constant:0.0];
    NSLayoutConstraint *constraint3 = [NSLayoutConstraint constraintWithItem:self.loadInterstitialButton
                                                                   attribute:NSLayoutAttributeCenterY
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:anchorView
                                                                   attribute:NSLayoutAttributeCenterY
                                                                  multiplier:1.0
                                                                    constant:0.0];
    self.loadInterstitialButton.translatesAutoresizingMaskIntoConstraints = NO;
    [anchorView addConstraint:constraint1];
    [anchorView addConstraint:constraint2];
    [anchorView addConstraint:constraint3];
}

- (void)clearBannerAdView {
    if (self.bannerAdView) {
        [self.bannerAdView removeFromSuperview];
    }
    self.bannerAdView.delegate = nil;
    self.bannerAdView = nil;
}

- (void)clearInterstitialAd {
    self.interstitialAd.delegate = nil;
    self.interstitialAd = nil;
    if (self.loadInterstitialButton) {
        self.loadInterstitialButton = nil;
        [self.loadInterstitialButton removeFromSuperview];
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Everytime the tableView asks for the cell height, it's because it needs the information to lay itself out.
    // In theory, this method should be called *exactly* each time the subviews needs to be positioned/repositioned
    
    if (self.bannerAdView) {
        // ScrollView width should be the banner width or the tableView width, whichever is greater
        CGSize bannerSize = self.bannerAdView.frame.size;
        CGSize tableSize = self.tableView.frame.size;
        CGFloat svWidth = (bannerSize.width > tableSize.width) ? bannerSize.width : tableSize.width;
        // ScrollView height should be the banner height or the tableView height, whichever is greater. This will also correspond to the cell height (which is returned).
        CGFloat svHeight = (bannerSize.height > tableSize.height) ? bannerSize.height : tableSize.height;
        
        self.scrollView.contentSize = CGSizeMake(svWidth, svHeight); // Set content size to cell dimensions
        
        CGFloat centerX = (tableSize.width - bannerSize.width) / 2.0;
        CGFloat centerY = (tableSize.height - bannerSize.height) / 2.0;
        
        // Do not allow negative/offscreen values for x and y
        
        if (centerY < 0) {
            centerY = 0.0;
        }
        
        if (centerX < 0) {
            centerX = 0.0;
        }
        
        // Center banner in window, with equal whitespace on either side
        [self.bannerAdView setFrame:CGRectMake(centerX,
                                               centerY,
                                               bannerSize.width,
                                               bannerSize.height)];
        
        return svHeight;
    } else { // Not a banner, so scrollview size should be the visible table view size
        CGFloat svWidth = self.tableView.frame.size.width;
        CGFloat svHeight = self.tableView.frame.size.height;
        self.scrollView.contentSize = CGSizeMake(svWidth, svHeight); // Set content size to cell dimensions
        return svHeight; // cell height equal to tableView height
    }
}

- (IBAction)loadInterstitial:(UIButton *)sender {
    if (self.interstitialAd && self.interstitialAd.isReady) {
        [self.interstitialAd displayAdFromViewController:self];
        [self.loadInterstitialButton setHidden:YES];
    }
}

#pragma mark Delegate Methods

- (void)adFailedToDisplay:(ANInterstitialAd *)ad {
    ANLogDebug(@"adFailedToDisplay");
}

- (void)ad:(id<ANAdProtocol>)ad requestFailedWithError:(NSError *)error {
    ANLogDebug(@"adFailed: %@", [error localizedDescription]);
    [self.delegate ad:ad requestFailedWithError:error];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:kAppNexusSDKAppErrorTitle
                                                    message:[error localizedDescription]
                                                   delegate:self
                                          cancelButtonTitle:kAppNexusSDKAppErrorCancel
                                          otherButtonTitles:nil];
    [alert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    [self.refreshControl endRefreshing];
}

- (void)adDidReceiveAd:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adDidReceiveAd");
    [self.delegate adDidReceiveAd:ad];
    [self.refreshControl endRefreshing];
    if (self.interstitialAd) {
        [self.loadInterstitialButton setHidden:NO];
    }
}

- (void)adWasClicked:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adWasClicked");
}

- (void)adDidClose:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adDidClose");
}

- (void)adWillClose:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adWillClose");
}

- (void)adWillPresent:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adWillPresent");
}

- (void)adDidPresent:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adDidPresent");
}

- (void)adWillLeaveApplication:(id<ANAdProtocol>)ad {
    ANLogDebug(@"adWillLeaveApplication");
}

/*
    Explictly deallocating ad views on controller deallocation to avoid a memory leak.
 */
- (void)dealloc {
    [self clearBannerAdView];
    [self clearInterstitialAd];
}

@end
