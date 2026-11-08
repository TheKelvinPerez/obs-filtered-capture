#import <AppKit/AppKit.h>
#include <obs.h>
#include <assert.h>

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        assert(argc == 2);
        assert(obs_startup("en-US", NULL, NULL));
        struct obs_video_info video = {
            .graphics_module = FC_OBS_APP_PATH "/Contents/Frameworks/libobs-metal.dylib",
            .fps_num = 60, .fps_den = 1,
            .base_width = 1920, .base_height = 1080,
            .output_width = 1920, .output_height = 1080,
            .output_format = VIDEO_FORMAT_BGRA,
            .colorspace = VIDEO_CS_709, .range = VIDEO_RANGE_FULL,
            .scale_type = OBS_SCALE_BILINEAR,
        };
        assert(obs_reset_video(&video) == OBS_VIDEO_SUCCESS);
        obs_module_t *module = NULL;
        assert(obs_open_module(&module, argv[1], ".") == MODULE_SUCCESS);
        assert(obs_init_module(module));
        const char *id = "macos-filtered-capture";
        assert(strcmp(obs_source_get_display_name(id), "macOS Capture with App Exclusions") == 0);
        obs_data_t *defaults = obs_get_source_defaults(id);
        assert(obs_data_get_bool(defaults, "hide_obs"));
        obs_data_array_t *ids = obs_data_get_array(defaults, "excluded_apps");
        assert(obs_data_array_count(ids) == 1);
        obs_data_t *item = obs_data_array_item(ids, 0);
        assert(strcmp(obs_data_get_string(item, "value"), "io.simplelocalize.notch-prompter") == 0);
        obs_data_release(item);
        obs_data_array_release(ids);
        obs_data_release(defaults);
        obs_properties_t *properties = obs_get_source_properties(id);
        assert(obs_properties_get(properties, "display_uuid"));
        assert(obs_properties_get(properties, "excluded_apps"));
        assert(obs_properties_get(properties, "add_app"));
        obs_properties_destroy(properties);
        // An unconfigured source must stay blank and survive settings changes/removal.
        obs_source_t *source = obs_source_create(id, "Filtered capture smoke", NULL, NULL);
        assert(source);
        assert(obs_source_get_width(source) == 0 && obs_source_get_height(source) == 0);
        obs_data_t *settings = obs_source_get_settings(source);
        obs_data_set_bool(settings, "show_cursor", false);
        obs_source_update(source, settings);
        obs_data_release(settings);
        obs_source_release(source);
        for (int i = 0; i < 25; ++i) {
            source = obs_source_create(id, "Lifecycle stress", NULL, NULL);
            assert(source);
            obs_source_inc_showing(source);
            obs_source_dec_showing(source);
            obs_source_release(source);
        }
        obs_wait_for_destroy_queue();
        obs_shutdown();
        puts("PASS: actual libobs module load, registration, defaults, properties, unconfigured source lifecycle");
    }
    return 0;
}
