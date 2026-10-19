/*
 * SPDX-License-Identifier: CC0-1.0
 */
#include "lvgl.h"
#include "esp_brookesia.hpp"
#ifdef ESP_UTILS_LOG_TAG
#   undef ESP_UTILS_LOG_TAG
#endif
#define ESP_UTILS_LOG_TAG "BS:Particles"
#include "esp_lib_utils.h"
#include "particle.h"
#include "esp_brookesia_app_particles.hpp"

#define APP_NAME "Partikler"

// The Swift simulation's timestep (tickDt in ParticleEffects.swift) assumes this period
constexpr uint32_t PARTICLE_TICK_MS = 50;
// Fixed HSV value for every particle; per-particle hue/saturation come from Swift
constexpr uint8_t PARTICLE_VALUE = 100;
// Particles fainter than this (~0.02 alpha) aren't worth drawing
constexpr uint8_t PARTICLE_MIN_OPA = 6;

using namespace esp_brookesia::systems;

LV_IMG_DECLARE(esp_brookesia_app_icon_launcher_particles_112_112);

static particle_t particle_buf[PARTICLE_MAX_COUNT];
static int32_t particle_count = 0;

namespace esp_brookesia::apps {

Particles *Particles::_instance = nullptr;

Particles *Particles::requestInstance()
{
    if (_instance == nullptr) {
        _instance = new Particles();
    }
    return _instance;
}

Particles::Particles():
    App(APP_NAME, &esp_brookesia_app_icon_launcher_particles_112_112, true, false, false)
{
}

Particles::~Particles()
{
}

bool Particles::run(void)
{
    ESP_UTILS_LOGD("Run");

    // Everything created here is recorded by the core and cleaned up when the app closes
    lv_obj_t *screen = lv_screen_active();
    lv_obj_set_style_bg_color(screen, lv_color_black(), 0);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, 0);

    _canvas = lv_obj_create(screen);
    lv_obj_remove_style_all(_canvas);
    lv_obj_set_size(_canvas, LV_PCT(100), LV_PCT(100));
    lv_obj_remove_flag(_canvas, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(_canvas, onDraw, LV_EVENT_DRAW_POST, nullptr);

    particle_count = 0;
    _needs_reset = true;
    _timer = lv_timer_create(onTick, PARTICLE_TICK_MS, this);

    return true;
}

bool Particles::back(void)
{
    ESP_UTILS_LOGD("Back");

    ESP_UTILS_CHECK_FALSE_RETURN(notifyCoreClosed(), false, "Notify core closed failed");

    return true;
}

bool Particles::close(void)
{
    ESP_UTILS_LOGD("Close");

    // The core deletes the recorded timer and objects itself
    _timer = nullptr;
    _canvas = nullptr;

    return true;
}

bool Particles::pause(void)
{
    ESP_UTILS_LOGD("Pause");

    if (_timer != nullptr) {
        lv_timer_pause(_timer);
    }

    return true;
}

bool Particles::resume(void)
{
    ESP_UTILS_LOGD("Resume");

    if (_timer != nullptr) {
        lv_timer_resume(_timer);
    }

    return true;
}

void Particles::onTick(lv_timer_t *timer)
{
    Particles *app = static_cast<Particles *>(lv_timer_get_user_data(timer));
    if (app->_canvas == nullptr) {
        return;
    }

    particle_effect_tick(
        particle_buf, PARTICLE_MAX_COUNT, &particle_count,
        lv_obj_get_width(app->_canvas), lv_obj_get_height(app->_canvas),
        app->_needs_reset
    );
    app->_needs_reset = false;

    lv_obj_invalidate(app->_canvas);
}

// Draws whatever Swift put in particle_buf last tick, without knowing which effect produced it
void Particles::onDraw(lv_event_t *e)
{
    lv_obj_t *obj = static_cast<lv_obj_t *>(lv_event_get_target(e));
    lv_layer_t *layer = lv_event_get_layer(e);

    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);

    lv_draw_rect_dsc_t dsc;
    lv_draw_rect_dsc_init(&dsc);
    dsc.radius = 0;
    dsc.border_width = 0;

    for (int32_t i = 0; i < particle_count; i++) {
        const particle_t *p = &particle_buf[i];
        if (p->opa < PARTICLE_MIN_OPA) {
            continue;
        }

        dsc.bg_color = lv_color_hsv_to_rgb(p->hue, p->sat, PARTICLE_VALUE);
        dsc.bg_opa = p->opa;

        int32_t s = p->size;
        lv_area_t area;
        area.x1 = coords.x1 + p->sx - s / 2;
        area.y1 = coords.y1 + p->sy - s / 2;
        area.x2 = area.x1 + s - 1;
        area.y2 = area.y1 + s - 1;

        lv_draw_rect(layer, &dsc, &area);
    }
}

ESP_UTILS_REGISTER_PLUGIN_WITH_CONSTRUCTOR(systems::base::App, Particles, APP_NAME, []()
{
    return std::shared_ptr<Particles>(Particles::requestInstance(), [](Particles * p) {});
})

} // namespace esp_brookesia::apps
