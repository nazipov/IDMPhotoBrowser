//
//  IDMZoomingScrollView.m
//  IDMPhotoBrowser
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import "IDMZoomingScrollView.h"
#import "IDMPhotoBrowser.h"
#import "IDMPhoto.h"

// Declare private methods of browser
@interface IDMPhotoBrowser ()
- (UIImage *)imageForPhoto:(id<IDMPhoto>)photo;
- (void)cancelControlHiding;
- (void)hideControlsAfterDelay;
//- (void)toggleControls;
- (void)handleSingleTap;
@end

// Private methods and properties
@interface IDMZoomingScrollView ()
@property (nonatomic, weak) IDMPhotoBrowser *photoBrowser;
- (void)handleSingleTap:(CGPoint)touchPoint;
- (void)handleDoubleTap:(CGPoint)touchPoint;
@end

@implementation IDMZoomingScrollView

@synthesize photoImageView = _photoImageView, videoPlayerView = _videoPlayerView, videoPlayerLayer = _videoPlayerLayer, photoBrowser = _photoBrowser, photo = _photo, captionView = _captionView;

- (id)initWithPhotoBrowser:(IDMPhotoBrowser *)browser {
    if ((self = [super init])) {
        // Delegate
        self.photoBrowser = browser;
        
		// Tap view for background
		_tapView = [[IDMTapDetectingView alloc] initWithFrame:self.bounds];
		_tapView.tapDelegate = self;
		_tapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		_tapView.backgroundColor = [UIColor clearColor];
		[self addSubview:_tapView];

        // Video
        _videoPlayerView = [[IDMTapDetectingView alloc] initWithFrame:self.bounds];
        _videoPlayerView.tapDelegate = self;
        _videoPlayerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _videoPlayerView.backgroundColor = [UIColor clearColor];
        [self addSubview:_videoPlayerView];

        _videoPlayerLayer = [[AVPlayerLayer alloc] init];
        _videoPlayerLayer.backgroundColor = [UIColor clearColor].CGColor;
        [_videoPlayerLayer setFrame:_videoPlayerView.bounds];
        [_videoPlayerLayer setVideoGravity:AVLayerVideoGravityResizeAspect];
        [_videoPlayerView.layer addSublayer:_videoPlayerLayer];

		// Image view
		_photoImageView = [[IDMTapDetectingImageView alloc] initWithFrame:CGRectZero];
		_photoImageView.tapDelegate = self;
		_photoImageView.backgroundColor = [UIColor clearColor];
        if (@available(iOS 11.0, *)) {
            _photoImageView.accessibilityIgnoresInvertColors = YES;
        } else {
            // Fallback on earlier versions
        }
		[self addSubview:_photoImageView];
        
        //Add darg&drop in iOS 11
        if (@available(iOS 11.0, *)) {
            UIDragInteraction *drag = [[UIDragInteraction alloc] initWithDelegate: self];
            [_photoImageView addInteraction:drag];
            [_videoPlayerView addInteraction:drag];
        }
        
        CGRect screenBound = [[UIScreen mainScreen] bounds];
        CGFloat screenWidth = screenBound.size.width;
        CGFloat screenHeight = screenBound.size.height;
        
        if ([[UIApplication sharedApplication] statusBarOrientation] == UIInterfaceOrientationLandscapeLeft || [[UIApplication sharedApplication] statusBarOrientation] == UIInterfaceOrientationLandscapeRight) {
            screenWidth = screenBound.size.height;
            screenHeight = screenBound.size.width;
        }
        
        // Progress view
        _progressView = [[DACircularProgressView alloc] initWithFrame:CGRectMake((screenWidth-35.)/2., (screenHeight-35.)/2, 35.0f, 35.0f)];
        [_progressView setProgress:0.0f];
        _progressView.tag = 101;
        _progressView.thicknessRatio = 0.1;
        _progressView.roundedCorners = NO;
        _progressView.trackTintColor    = browser.trackTintColor    ? self.photoBrowser.trackTintColor    : [UIColor colorWithWhite:0.2 alpha:1];
        _progressView.progressTintColor = browser.progressTintColor ? self.photoBrowser.progressTintColor : [UIColor colorWithWhite:1.0 alpha:1];
        [self addSubview:_progressView];
        
		// Setup
		self.backgroundColor = [UIColor clearColor];
		self.delegate = self;
		self.showsHorizontalScrollIndicator = NO;
		self.showsVerticalScrollIndicator = NO;
		self.decelerationRate = UIScrollViewDecelerationRateFast;
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    
    return self;
}

- (void)setPhoto:(id<IDMPhoto>)photo {
    _photoImageView.image = nil; // Release image
    if (_photo != photo) {
        _photo = photo;
    }
    [self displayImage];
}

- (void)prepareForReuse {
    [_progressView setProgress:0 animated:NO];
    [_progressView setIndeterminate:NO];
    [_videoPlayerLayer.player removeObserver:self forKeyPath:@"status" context:nil];
    [_videoPlayerLayer.player pause];
    _videoPlayerLayer.player = NULL;
    self.photo = nil;
    [_captionView removeFromSuperview];
    self.captionView = nil;
}

#pragma mark - Drag & Drop

- (NSArray<UIDragItem *> *)dragInteraction:(UIDragInteraction *)interaction itemsForBeginningSession:(id<UIDragSession>)session NS_AVAILABLE_IOS(11.0) {
    return @[[[UIDragItem alloc] initWithItemProvider:[[NSItemProvider alloc] initWithObject:_photoImageView.image]]];
}

#pragma mark - Image

// Get and display image
- (void)displayImage {
	if (_photo) {
		// Reset
		self.maximumZoomScale = 1;
		self.minimumZoomScale = 1;
		self.zoomScale = 1;
        
		self.contentSize = CGSizeMake(0, 0);
		
		// Get image from browser as it handles ordering of fetching
		UIImage *img = [self.photoBrowser imageForPhoto:_photo];
		if (img) {
            // Hide video
            _videoPlayerView.hidden = YES;

            // Hide ProgressView
            //_progressView.alpha = 0.0f;
            [_progressView removeFromSuperview];
            
            // Set image
			_photoImageView.image = img;
			_photoImageView.hidden = NO;
            
            // Setup photo frame
			CGRect photoImageViewFrame;
			photoImageViewFrame.origin = CGPointZero;
			photoImageViewFrame.size = img.size;
            
			_photoImageView.frame = photoImageViewFrame;
			self.contentSize = photoImageViewFrame.size;

			// Set zoom to minimum zoom
			[self setMaxMinZoomScalesForCurrentBounds];
        } else if (_photo.videoURL != NULL) {
            // Hide ProgressView
            //_progressView.alpha = 0.0f;
            [_progressView setProgress:0.3 animated:YES];
            [_progressView setIndeterminateDuration:0.7f];
            [_progressView setIndeterminate:YES];

            _photoImageView.hidden = YES;
            _videoPlayerView.hidden = NO;

            [_videoPlayerLayer.player pause];
            _videoPlayerLayer.player = NULL;
            AVPlayer *player = [AVPlayer playerWithURL:_photo.videoURL];
            [_videoPlayerLayer setPlayer:player];

            [player seekToTime:kCMTimeZero];
            [player play];

            [player addObserver:self forKeyPath:@"status" options:0 context:nil];
        } else {
			// Hide image view
			_photoImageView.hidden = YES;
            
            _progressView.alpha = 1.0f;
		}

		[self setNeedsLayout];
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == _videoPlayerLayer.player && [keyPath isEqualToString:@"status"]) {
        if (_videoPlayerLayer.player.status == AVPlayerStatusReadyToPlay) {
            [_progressView removeFromSuperview];
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)setProgress:(CGFloat)progress forPhoto:(IDMPhoto*)photo {
    IDMPhoto *p = (IDMPhoto*)self.photo;

    if ([photo.photoURL.absoluteString isEqualToString:p.photoURL.absoluteString]) {
        if (_progressView.progress < progress) {
            [_progressView setProgress:progress animated:YES];
        }
    }
}

// Image failed so just show black!
- (void)displayImageFailure {
    [_progressView removeFromSuperview];
}

#pragma mark - Setup

- (void)setMaxMinZoomScalesForCurrentBounds {
	// Reset
	self.maximumZoomScale = 1;
	self.minimumZoomScale = 1;
	self.zoomScale = 1;
    
	// Bail
	if (_photoImageView.image == nil) return;
    
	// Sizes
	CGSize boundsSize = self.bounds.size;
	boundsSize.width -= 0.1;
	boundsSize.height -= 0.1;
	
    CGSize imageSize = _photoImageView.frame.size;
    
    // Calculate Min
    CGFloat xScale = boundsSize.width / imageSize.width;    // the scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / imageSize.height;  // the scale needed to perfectly fit the image height-wise
    CGFloat minScale = MIN(xScale, yScale);                 // use minimum of these to allow the image to become fully visible
    
	// If image is smaller than the screen then ensure we show it at
	// min scale of 1
	if (xScale > 1 && yScale > 1) {
		//minScale = 1.0;
	}
    
	// Calculate Max
	CGFloat maxScale = 4.0; // Allow double scale
    // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
    // maximum zoom scale to 0.5.
	if ([UIScreen instancesRespondToSelector:@selector(scale)]) {
		maxScale = maxScale / [[UIScreen mainScreen] scale];
		
		if (maxScale < minScale) {
			maxScale = minScale * 2;
		}
	}

	// Calculate Max Scale Of Double Tap
	CGFloat maxDoubleTapZoomScale = 4.0 * minScale; // Allow double scale
    // on high resolution screens we have double the pixel density, so we will be seeing every pixel if we limit the
    // maximum zoom scale to 0.5.
	if ([UIScreen instancesRespondToSelector:@selector(scale)]) {
        maxDoubleTapZoomScale = maxDoubleTapZoomScale / [[UIScreen mainScreen] scale];
        
        if (maxDoubleTapZoomScale < minScale) {
            maxDoubleTapZoomScale = minScale * 2;
        }
    }
    
    // Make sure maxDoubleTapZoomScale isn't larger than maxScale
    maxDoubleTapZoomScale = MIN(maxDoubleTapZoomScale, maxScale);
    
	// Set
	self.maximumZoomScale = maxScale;
	self.minimumZoomScale = minScale;
	self.zoomScale = minScale;
	self.maximumDoubleTapZoomScale = maxDoubleTapZoomScale;
    
	// Reset position
	_photoImageView.frame = CGRectMake(0, 0, _photoImageView.frame.size.width, _photoImageView.frame.size.height);
	[self setNeedsLayout];    
}

#pragma mark - Layout

- (void)layoutSubviews {
	// Update tap view frame
	_tapView.frame = self.bounds;

    _videoPlayerView.frame = self.bounds;
    _videoPlayerLayer.frame = _videoPlayerView.bounds;

	// Super
	[super layoutSubviews];
    
    // Center the image as it becomes smaller than the size of the screen
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = _photoImageView.frame;
    
    // Horizontally
    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = floorf((boundsSize.width - frameToCenter.size.width) / 2.0);
	} else {
        frameToCenter.origin.x = 0;
	}
    
    // Vertically
    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = floorf((boundsSize.height - frameToCenter.size.height) / 2.0);
	} else {
        frameToCenter.origin.y = 0;
	}
    
	// Center
	if (!CGRectEqualToRect(_photoImageView.frame, frameToCenter))
		_photoImageView.frame = frameToCenter;
}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return _photoImageView;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[_photoBrowser cancelControlHiding];
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
	[_photoBrowser cancelControlHiding];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	[_photoBrowser hideControlsAfterDelay];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

#pragma mark - Tap Detection

- (void)handleSingleTap:(CGPoint)touchPoint {
//	[_photoBrowser performSelector:@selector(toggleControls) withObject:nil afterDelay:0.2];
	[_photoBrowser performSelector:@selector(handleSingleTap) withObject:nil afterDelay:0.2];
}

- (void)handleDoubleTap:(CGPoint)touchPoint {
	
	// Cancel any single tap handling
	[NSObject cancelPreviousPerformRequestsWithTarget:_photoBrowser];
	
	// Zoom
	if (self.zoomScale == self.maximumDoubleTapZoomScale) {
		
		// Zoom out
		[self setZoomScale:self.minimumZoomScale animated:YES];
		
	} else {
		
		// Zoom in
		CGSize targetSize = CGSizeMake(self.frame.size.width / self.maximumDoubleTapZoomScale, self.frame.size.height / self.maximumDoubleTapZoomScale);
		CGPoint targetPoint = CGPointMake(touchPoint.x - targetSize.width / 2, touchPoint.y - targetSize.height / 2);
		
		[self zoomToRect:CGRectMake(targetPoint.x, targetPoint.y, targetSize.width, targetSize.height) animated:YES];
		
	}
	
	// Delay controls
	[_photoBrowser hideControlsAfterDelay];
}

// Image View
- (void)imageView:(UIImageView *)imageView singleTapDetected:(UITouch *)touch { 
    [self handleSingleTap:[touch locationInView:imageView]];
}
- (void)imageView:(UIImageView *)imageView doubleTapDetected:(UITouch *)touch {
    [self handleDoubleTap:[touch locationInView:imageView]];
}

// Background View
- (void)view:(UIView *)view singleTapDetected:(UITouch *)touch {
    [self handleSingleTap:[touch locationInView:view]];
}
- (void)view:(UIView *)view doubleTapDetected:(UITouch *)touch {
    [self handleDoubleTap:[touch locationInView:view]];
}

@end
