/* SPDX-License-Identifier: GPL-2.0-or-later
 * IOSurface import/render approach follows OBS Studio 33.0.1 mac-capture.
 * See THIRD_PARTY.md for attribution.
 */
#import <AppKit/AppKit.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <IOSurface/IOSurface.h>
#include <obs-module.h>
#include <util/platform.h>
#include <stdatomic.h>
#import "capture-policy.h"

OBS_DECLARE_MODULE()

#define FCLOG(level, ...) blog(level, "[filtered-capture] " __VA_ARGS__)

@interface FCSession : NSObject <SCStreamOutput, SCStreamDelegate> {
    NSLock *_lock;
    dispatch_queue_t _control;
    dispatch_queue_t _frames;
    SCStream *_stream;
    IOSurfaceRef _latest;
    BOOL _running;
    BOOL _accepting;
    BOOL _enabled;
    BOOL _closed;
    NSUInteger _generation;
    NSString *_displayUUID;
    NSSet<NSString *> *_excluded;
    BOOL _cursor;
    uint32_t _fpsNum, _fpsDen;
    NSUInteger _maximumWidth;
    NSMutableArray *_observers;
    uint64_t _framesReceived;
}
- (void)configureDisplay:(NSString *)uuid excluded:(NSSet *)excluded cursor:(BOOL)cursor
                 fpsNum:(uint32_t)num fpsDen:(uint32_t)den maximumWidth:(NSUInteger)width;
- (void)restart;
- (void)setEnabled:(BOOL)enabled;
- (void)shutdown;
- (BOOL)isRunningGeneration:(NSUInteger)generation;
- (IOSurfaceRef)copySurfaceGeneration:(NSUInteger *)generation CF_RETURNS_RETAINED;
@end

@implementation FCSession
- (instancetype)init
{
    if ((self = [super init])) {
        _lock = [NSLock new];
        _control = dispatch_queue_create("local.filtered-capture.control", DISPATCH_QUEUE_SERIAL);
        _frames = dispatch_queue_create("local.filtered-capture.frames", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _observers = [NSMutableArray array];
        __weak FCSession *weakSelf = self;
        NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
        for (NSString *name in @[NSWorkspaceDidLaunchApplicationNotification, NSWorkspaceDidTerminateApplicationNotification, NSWorkspaceDidWakeNotification]) {
            id token = [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                FCSession *session = weakSelf;
                if (!session) return;
                NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
                [session->_lock lock];
                BOOL affected = !app || [session->_excluded containsObject:app.bundleIdentifier];
                [session->_lock unlock];
                if (affected) [session restart];
            }];
            [_observers addObject:token];
        }
        [_observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidChangeScreenParametersNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [weakSelf restart];
        }]];
    }
    return self;
}

- (void)clearSurfaceLocked
{
    if (_latest) {
        IOSurfaceDecrementUseCount(_latest);
        CFRelease(_latest);
        _latest = NULL;
    }
}

- (void)configureDisplay:(NSString *)uuid excluded:(NSSet *)excluded cursor:(BOOL)cursor
                 fpsNum:(uint32_t)num fpsDen:(uint32_t)den maximumWidth:(NSUInteger)width
{
    [_lock lock];
    _displayUUID = [uuid copy];
    _excluded = [excluded copy];
    _cursor = cursor;
    _fpsNum = num ?: 60;
    _fpsDen = den ?: 1;
    _maximumWidth = width;
    [_lock unlock];
    [self restart];
}

- (void)restart
{
    [_lock lock];
    if (_closed) { [_lock unlock]; return; }
    NSUInteger generation = ++_generation;
    _running = NO;
    _accepting = NO;
    [self clearSurfaceLocked];
    [_lock unlock];
    dispatch_async(_control, ^{
        [self beginGeneration:generation];
    });
}

- (void)setEnabled:(BOOL)enabled
{
    [_lock lock];
    _enabled = enabled;
    [_lock unlock];
    [self restart];
}

- (void)beginGeneration:(NSUInteger)generation
{
    [_lock lock];
    if (_closed || generation != _generation) { [_lock unlock]; return; }
    SCStream *old = _stream;
    _stream = nil;
    NSString *uuid = _displayUUID;
    NSSet *excluded = _excluded;
    BOOL cursor = _cursor;
    uint32_t num = _fpsNum, den = _fpsDen;
    NSUInteger maximumWidth = _maximumWidth;
    BOOL enabled = _enabled;
    [_lock unlock];
    if (old) [old stopCaptureWithCompletionHandler:^(NSError *error) {}];
    if (!enabled || !uuid.length) return;

    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(self->_control, ^{
            [self->_lock lock];
            BOOL stale = self->_closed || generation != self->_generation;
            [self->_lock unlock];
            if (stale) return;
            if (error) {
                FCLOG(LOG_ERROR, "Cannot enumerate capture content: %s", error.localizedDescription.UTF8String);
                return;
            }
            SCDisplay *selected = nil;
            for (SCDisplay *display in content.displays) {
                CFUUIDRef displayUUID = CGDisplayCreateUUIDFromDisplayID(display.displayID);
                NSString *candidate = displayUUID ? CFBridgingRelease(CFUUIDCreateString(NULL, displayUUID)) : nil;
                if (displayUUID) CFRelease(displayUUID);
                if ([uuid isEqualToString:candidate]) { selected = display; break; }
            }
            if (!selected) {
                FCLOG(LOG_WARNING, "Selected display unavailable; output remains blank (no fallback display).");
                return;
            }
            NSMutableArray *apps = [NSMutableArray array];
            for (SCRunningApplication *app in content.applications)
                if ([excluded containsObject:app.bundleIdentifier]) [apps addObject:app];
            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:selected excludingApplications:apps exceptingWindows:@[]];
            SCStreamConfiguration *config = [SCStreamConfiguration new];
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(selected.displayID);
            size_t width = mode ? CGDisplayModeGetPixelWidth(mode) : selected.width;
            size_t height = mode ? CGDisplayModeGetPixelHeight(mode) : selected.height;
            if (mode) CGDisplayModeRelease(mode);
            if (maximumWidth && width > maximumWidth) {
                height = MAX(2, (size_t)llround((double)height * maximumWidth / width));
                width = maximumWidth;
            }
            config.width = width;
            config.height = height;
            config.minimumFrameInterval = CMTimeMake(den, num);
            config.queueDepth = 5;
            config.showsCursor = cursor;
            config.pixelFormat = kCVPixelFormatType_32BGRA;
            config.colorSpaceName = kCGColorSpaceSRGB;
            config.capturesAudio = NO;
            SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            NSError *addError = nil;
            if (![stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self->_frames error:&addError]) {
                FCLOG(LOG_ERROR, "Cannot attach capture output: %s", addError.localizedDescription.UTF8String);
                return;
            }
            [self->_lock lock];
            if (self->_closed || generation != self->_generation) { [self->_lock unlock]; return; }
            self->_stream = stream;
            self->_accepting = YES;
            [self->_lock unlock];
            [stream startCaptureWithCompletionHandler:^(NSError *startError) {
                [self->_lock lock];
                BOOL current = !self->_closed && generation == self->_generation && stream == self->_stream;
                if (current) {
                    self->_running = startError == nil;
                    if (startError) { self->_accepting = NO; [self clearSurfaceLocked]; }
                }
                [self->_lock unlock];
                if (!current) { [stream stopCaptureWithCompletionHandler:^(NSError *error) {}]; return; }
                if (startError) FCLOG(LOG_ERROR, "Cannot start capture: %s", startError.localizedDescription.UTF8String);
                else FCLOG(LOG_INFO, "Started %zux%zu at %u/%u fps; %zu running app processes excluded; GPU IOSurface path, SDR BGRA.", width, height, num, den, (size_t)apps.count);
            }];
        });
    }];
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer ofType:(SCStreamOutputType)type
{
    if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sampleBuffer)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    NSNumber *status = [attachments.firstObject objectForKey:SCStreamFrameInfoStatus];
    if (!status || status.integerValue != SCFrameStatusComplete) return;
    CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixels) return;
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixels);
    if (!surface) return;
    [_lock lock];
    if (_accepting && !_closed && stream == _stream) {
        CFRetain(surface);
        IOSurfaceIncrementUseCount(surface);
        [self clearSurfaceLocked];
        _latest = surface;
        ++_framesReceived;
    }
    [_lock unlock];
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error
{
    [_lock lock];
    if (stream == _stream) { _running = NO; _accepting = NO; [self clearSurfaceLocked]; }
    [_lock unlock];
    FCLOG(LOG_WARNING, "Capture stopped; output blank: %s. Use Restart capture to retry.", error.localizedDescription.UTF8String);
}

- (BOOL)isRunningGeneration:(NSUInteger)generation { [_lock lock]; BOOL value = _running && !_closed && generation == _generation; [_lock unlock]; return value; }
- (IOSurfaceRef)copySurfaceGeneration:(NSUInteger *)generation
{
    [_lock lock];
    IOSurfaceRef surface = (_running && !_closed) ? _latest : NULL;
    *generation = _generation;
    if (surface) { CFRetain(surface); IOSurfaceIncrementUseCount(surface); }
    [_lock unlock];
    return surface;
}
- (void)shutdown
{
    [_lock lock];
    _closed = YES;
    ++_generation;
    _running = NO;
    _accepting = NO;
    SCStream *stream = _stream;
    _stream = nil;
    [self clearSurfaceLocked];
    uint64_t received = _framesReceived;
    [_lock unlock];
    for (id observer in _observers) {
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    [_observers removeAllObjects];
    if (stream) [stream stopCaptureWithCompletionHandler:^(NSError *error) {}];
    // Drain queued control work before the OBS source releases its ownership.
    dispatch_sync(_control, ^{});
    FCLOG(LOG_INFO, "Source closed; received %llu complete frames.", (unsigned long long)received);
}
- (void)dealloc { if (_latest) { IOSurfaceDecrementUseCount(_latest); CFRelease(_latest); } }
@end

struct fc_source {
    void *session;
    gs_texture_t *texture;
    IOSurfaceRef surface;
    atomic_uint width, height;
    NSUInteger generation;
};

static FCSession *session_for(struct fc_source *source) { return (__bridge FCSession *)source->session; }
static const char *fc_name(void *unused) { return "macOS Capture with App Exclusions"; }

static void fc_defaults(obs_data_t *settings)
{
    obs_data_set_default_bool(settings, "show_cursor", true);
    obs_data_set_default_bool(settings, "hide_obs", true);
    obs_data_set_default_string(settings, "display_uuid", "");
    obs_data_set_default_int(settings, "maximum_width", 0);
    obs_data_array_t *ids = obs_data_array_create();
    obs_data_t *item = obs_data_create();
    obs_data_set_string(item, "value", "io.simplelocalize.notch-prompter");
    obs_data_array_push_back(ids, item);
    obs_data_set_default_array(settings, "excluded_apps", ids);
    obs_data_release(item);
    obs_data_array_release(ids);
}

static void fc_update(void *data, obs_data_t *settings)
{
    struct fc_source *source = data;
    NSMutableArray *values = [NSMutableArray array];
    obs_data_array_t *ids = obs_data_get_array(settings, "excluded_apps");
    for (size_t i = 0; i < obs_data_array_count(ids); ++i) {
        obs_data_t *item = obs_data_array_item(ids, i);
        [values addObject:@(obs_data_get_string(item, "value"))];
        obs_data_release(item);
    }
    obs_data_array_release(ids);
    NSSet *excluded = FCExcludedBundleIDs(values, obs_data_get_bool(settings, "hide_obs"), NSBundle.mainBundle.bundleIdentifier);
    struct obs_video_info video = {0};
    obs_get_video_info(&video);
    [session_for(source) configureDisplay:@(obs_data_get_string(settings, "display_uuid")) excluded:excluded
                                  cursor:obs_data_get_bool(settings, "show_cursor") fpsNum:video.fps_num fpsDen:video.fps_den
                            maximumWidth:(NSUInteger)MAX(0, obs_data_get_int(settings, "maximum_width"))];
}

static void *fc_create(obs_data_t *settings, obs_source_t *obsSource)
{
    struct fc_source *source = bzalloc(sizeof(*source));
    source->session = (__bridge_retained void *)[FCSession new];
    fc_update(source, settings);
    return source;
}

static void clear_gpu(struct fc_source *source)
{
    if (source->texture) { gs_texture_destroy(source->texture); source->texture = NULL; }
    if (source->surface) { IOSurfaceDecrementUseCount(source->surface); CFRelease(source->surface); source->surface = NULL; }
}
static void fc_destroy(void *data)
{
    struct fc_source *source = data;
    if (!source) return;
    FCSession *session = CFBridgingRelease(source->session);
    [session shutdown];
    obs_enter_graphics();
    clear_gpu(source);
    obs_leave_graphics();
    bfree(source);
}

static void fc_tick(void *data, float seconds)
{
    struct fc_source *source = data;
    NSUInteger generation = 0;
    IOSurfaceRef surface = [session_for(source) copySurfaceGeneration:&generation];
    obs_enter_graphics();
    if (!surface) { clear_gpu(source); obs_leave_graphics(); return; }
    if (surface != source->surface) {
        uint32_t width = (uint32_t)IOSurfaceGetWidth(surface), height = (uint32_t)IOSurfaceGetHeight(surface);
        if (source->texture && (width != source->width || height != source->height)) {
            gs_texture_destroy(source->texture);
            source->texture = NULL;
        }
        BOOL bound = source->texture ? gs_texture_rebind_iosurface(source->texture, surface) : NO;
        if (!bound) {
            if (source->texture) gs_texture_destroy(source->texture);
            source->texture = gs_texture_create_from_iosurface(surface);
        }
        if (source->surface) { IOSurfaceDecrementUseCount(source->surface); CFRelease(source->surface); }
        source->surface = surface;
        source->width = width;
        source->height = height;
    } else { IOSurfaceDecrementUseCount(surface); CFRelease(surface); }
    source->generation = generation;
    obs_leave_graphics();
}

static void fc_render(void *data, gs_effect_t *unused)
{
    struct fc_source *source = data;
    if (!source->texture || ![session_for(source) isRunningGeneration:source->generation]) return;
    gs_effect_t *effect = obs_get_base_effect(gs_get_device_type() == GS_DEVICE_OPENGL ? OBS_EFFECT_DEFAULT_RECT : OBS_EFFECT_DEFAULT);
    BOOL previous = gs_framebuffer_srgb_enabled();
    gs_enable_framebuffer_srgb(true);
    gs_effect_set_texture_srgb(gs_effect_get_param_by_name(effect, "image"), source->texture);
    while (gs_effect_loop(effect, "Draw")) gs_draw_sprite(source->texture, 0, 0, 0);
    gs_enable_framebuffer_srgb(previous);
}
static uint32_t fc_width(void *data) { return ((struct fc_source *)data)->width; }
static uint32_t fc_height(void *data) { return ((struct fc_source *)data)->height; }
static void fc_show(void *data) { [session_for(data) setEnabled:YES]; }
static void fc_hide(void *data) { [session_for(data) setEnabled:NO]; }

static bool fc_restart(obs_properties_t *props, obs_property_t *property, void *data)
{
    if (data) [session_for(data) restart];
    return false;
}
static bool fc_add_app(obs_properties_t *props, obs_property_t *property, obs_data_t *settings)
{
    const char *selected = obs_data_get_string(settings, "add_app");
    if (!*selected) return false;
    NSString *bundleID = @(selected);
    obs_data_array_t *ids = obs_data_get_array(settings, "excluded_apps");
    if (!ids) ids = obs_data_array_create();
    bool exists = false;
    for (size_t i = 0; i < obs_data_array_count(ids); ++i) {
        obs_data_t *item = obs_data_array_item(ids, i);
        exists |= [bundleID isEqualToString:@(obs_data_get_string(item, "value"))];
        obs_data_release(item);
    }
    if (!exists) {
        obs_data_t *item = obs_data_create();
        obs_data_set_string(item, "value", bundleID.UTF8String);
        obs_data_array_push_back(ids, item);
        obs_data_release(item);
    }
    obs_data_set_array(settings, "excluded_apps", ids);
    obs_data_array_release(ids);
    obs_data_set_string(settings, "add_app", "");
    return true;
}

static obs_properties_t *fc_properties(void *data)
{
    obs_properties_t *props = obs_properties_create();
    obs_property_t *displays = obs_properties_add_list(props, "display_uuid", "Display", OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_STRING);
    obs_property_list_add_string(displays, "Choose a display", "");
    for (NSScreen *screen in NSScreen.screens) {
        CGDirectDisplayID display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
        if (!uuid) continue;
        NSString *value = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
        CFRelease(uuid);
        NSString *label = [NSString stringWithFormat:@"%@ (%ux%u)", screen.localizedName, (unsigned)CGDisplayPixelsWide(display), (unsigned)CGDisplayPixelsHigh(display)];
        obs_property_list_add_string(displays, label.UTF8String, value.UTF8String);
    }
    obs_properties_add_bool(props, "show_cursor", "Show cursor");
    obs_properties_add_bool(props, "hide_obs", "Exclude OBS windows");
    obs_properties_add_editable_list(props, "excluded_apps", "Excluded application bundle IDs", OBS_EDITABLE_LIST_TYPE_STRINGS, NULL, NULL);
    obs_property_t *apps = obs_properties_add_list(props, "add_app", "Add running application to exclusions", OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_STRING);
    obs_property_list_add_string(apps, "Choose an application", "");
    NSMutableSet *seen = [NSMutableSet set];
    NSArray *running = [NSWorkspace.sharedWorkspace.runningApplications sortedArrayUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        return [(a.localizedName ?: @"") localizedCaseInsensitiveCompare:(b.localizedName ?: @"")];
    }];
    for (NSRunningApplication *app in running) {
        if (!app.bundleIdentifier.length || [seen containsObject:app.bundleIdentifier]) continue;
        [seen addObject:app.bundleIdentifier];
        NSString *label = [NSString stringWithFormat:@"%@ (%@)", app.localizedName ?: app.bundleIdentifier, app.bundleIdentifier];
        obs_property_list_add_string(apps, label.UTF8String, app.bundleIdentifier.UTF8String);
    }
    obs_property_set_modified_callback(apps, fc_add_app);
    obs_property_t *resolution = obs_properties_add_list(props, "maximum_width", "Capture width limit", OBS_COMBO_TYPE_LIST, OBS_COMBO_FORMAT_INT);
    obs_property_list_add_int(resolution, "Native display resolution", 0);
    obs_property_list_add_int(resolution, "1920 pixels", 1920);
    obs_property_list_add_int(resolution, "2560 pixels", 2560);
    obs_property_list_add_int(resolution, "3840 pixels", 3840);
    obs_properties_add_text(props, "info", "Uses OBS frame rate. SDR video only; keep your existing audio sources. Output goes blank while capture restarts. Excluded app launches trigger a filter refresh; do a privacy test before recording.", OBS_TEXT_INFO);
    obs_properties_add_button2(props, "restart", "Restart capture / refresh applications", fc_restart, data);
    return props;
}

bool obs_module_load(void)
{
    struct obs_source_info info = {
        .id = "macos-filtered-capture",
        .type = OBS_SOURCE_TYPE_INPUT,
        .output_flags = OBS_SOURCE_VIDEO | OBS_SOURCE_CUSTOM_DRAW | OBS_SOURCE_DO_NOT_DUPLICATE,
        .get_name = fc_name,
        .create = fc_create,
        .destroy = fc_destroy,
        .update = fc_update,
        .get_defaults = fc_defaults,
        .get_properties = fc_properties,
        .video_tick = fc_tick,
        .video_render = fc_render,
        .get_width = fc_width,
        .get_height = fc_height,
        .show = fc_show,
        .hide = fc_hide,
        .icon_type = OBS_ICON_TYPE_DESKTOP_CAPTURE,
    };
    obs_register_source(&info);
    FCLOG(LOG_INFO, "Loaded version 0.1.0 (OBS 33 headers; macOS 13+).");
    return true;
}
MODULE_EXPORT const char *obs_module_description(void) { return "Direct ScreenCaptureKit display capture with application exclusions"; }
