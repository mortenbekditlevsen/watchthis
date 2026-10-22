// The faces screen: shows one face and slides to the next/previous one on a horizontal swipe. Only the face on
// screen exists (plus, for the 250 ms of a slide, the one leaving).

private let slideDuration: UInt32 = 250
private let toastDuration: UInt32 = 1200

final class Carousel {
    let screen: LVObj
    private var ids: [String]
    private var index: Int
    private var current: RenderedFace?
    private var leaving: RenderedFace?
    private var slideDirection: Int32 = 1
    private var timer: OpaquePointer?
    private let toast: LVObj
    private var toastShownAt: UInt32 = 0
    private let birthday: BirthdayDecoration

    init() {
        screen = lv_obj_create(nil)!
        lv_obj_remove_style_all(screen)
        lv_obj_set_style_bg_color(screen, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
        // The power manager's "idle sleep allowed here" flag (main/power_manager.hpp)
        lv_obj_add_flag(screen, LV_OBJ_FLAG_USER_1)

        toast = lv_label_create(screen)!
        lv_obj_set_style_text_font(toast, wf_builtin_font(20), partMain)
        lv_obj_set_style_text_color(toast, lv_color_white(), partMain)
        lv_obj_set_style_bg_color(toast, lv_color_black(), partMain)
        lv_obj_set_style_bg_opa(toast, 180, partMain)
        lv_obj_set_style_radius(toast, 12, partMain)
        lv_obj_set_style_pad_hor(toast, 14, partMain)
        lv_obj_set_style_pad_ver(toast, 6, partMain)
        lv_obj_align(toast, LV_ALIGN_TOP_MID, 0, 24)
        lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN)
        birthday = BirthdayDecoration(screen: screen)

        let visible = FaceStore.visible()
        ids = visible.ids
        index = visible.active
        wf_atomic_store(&facesChanged, 0)

        lv_obj_add_event_cb(screen, { _ in
            carousel?.onGesture()
        }, LV_EVENT_GESTURE, nil)

        showCurrent()
        birthday.update(currentWallTime())
        timer = lv_timer_create({ _ in carousel?.tick() }, current?.updatePeriod ?? 1000, nil)
    }

    func stop() {
        birthday.stop()
        if let timer { lv_timer_delete(timer) }
        timer = nil
        finishSlide()
    }

    private func makeFace(_ id: String) -> RenderedFace {
        let face = FaceStore.load(id) ?? WatchFace.classic
        let start = lv_tick_get()
        let rendered = RenderedFace(face: face, parent: screen)
        lv_obj_move_background(rendered.root) // under the toast
        print("watch_faces: \(face.id) built in \(lv_tick_elaps(start)) ms, free heap " +
              "\(heap_caps_get_free_size(UInt32(MALLOC_CAP_INTERNAL)) / 1024) KB")
        return rendered
    }

    private func showCurrent() {
        if let current { lv_obj_delete(current.root) }
        current = makeFace(ids[index])
        if let timer, let current { lv_timer_set_period(timer, current.updatePeriod) }
    }

    private func tick() {
        if wf_atomic_load(&facesChanged) != 0 {
            wf_atomic_store(&facesChanged, 0)
            ImageWorker.failedAssets.removeAll()
            finishSlide()
            let previousID = ids[index]
            let visible = FaceStore.visible()
            ids = visible.ids
            index = ids.firstIndex { $0.utf8.elementsEqual(previousID.utf8) } ?? visible.active
            showCurrent()
            return
        }
        let now = currentWallTime()
        current?.update(now)
        birthday.update(now)
        if !lv_obj_has_flag(toast, LV_OBJ_FLAG_HIDDEN) && lv_tick_elaps(toastShownAt) > toastDuration {
            lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN)
        }
    }

    // MARK: - Swiping

    private func onGesture() {
        let dir = lv_indev_get_gesture_dir(lv_indev_active())
        if dir == LV_DIR_LEFT {
            slide(by: 1)
        } else if dir == LV_DIR_RIGHT {
            slide(by: -1)
        }
    }

    private func slide(by step: Int) {
        guard ids.count > 1 else { return }
        finishSlide()
        index = (index + step + ids.count) % ids.count
        FaceStore.saveActive(index, ids: ids)
        leaving = current
        slideDirection = Int32(step)
        current = makeFace(ids[index])
        if let timer, let current { lv_timer_set_period(timer, current.updatePeriod) }
        setSlide(0)

        var anim = lv_anim_t()
        lv_anim_init(&anim)
        lv_anim_set_var(&anim, UnsafeMutableRawPointer(current!.root))
        lv_anim_set_values(&anim, 0, Int32(WatchScreen.width))
        lv_anim_set_duration(&anim, slideDuration)
        lv_anim_set_path_cb(&anim, lv_anim_path_ease_out)
        lv_anim_set_exec_cb(&anim) { _, value in carousel?.setSlide(value) }
        lv_anim_set_completed_cb(&anim) { _ in carousel?.finishSlide() }
        _ = lv_anim_start(&anim)

        lvSetText(toast, current!.face.name)
        lv_obj_remove_flag(toast, LV_OBJ_FLAG_HIDDEN)
        lv_obj_move_foreground(toast)
        toastShownAt = lv_tick_get()
    }

    /// `progress` 0...WatchScreen.width: how far the new face has slid in
    private func setSlide(_ progress: Int32) {
        let w = Int32(WatchScreen.width)
        if let current { lv_obj_set_x(current.root, slideDirection * (w - progress)) }
        if let leaving { lv_obj_set_x(leaving.root, -slideDirection * progress) }
    }

    private func finishSlide() {
        guard let leaving else { return }
        if let current {
            _ = lv_anim_delete(UnsafeMutableRawPointer(current.root), nil)
            lv_obj_set_x(current.root, 0)
        }
        self.leaving = nil
        lv_obj_delete(leaving.root)
    }
}

nonisolated(unsafe) private var carousel: Carousel?

@_cdecl("watch_faces_show")
public func watch_faces_show() {
    if carousel != nil { watch_faces_hide() }
    let c = Carousel()
    carousel = c
    lv_screen_load(c.screen)
}

@_cdecl("watch_faces_hide")
public func watch_faces_hide() {
    carousel?.stop()
    carousel = nil
}

@_cdecl("watch_faces_set_battery_source")
public func watch_faces_set_battery_source(_ source: (@convention(c) () -> Int32)?) {
    batterySource = source
}
