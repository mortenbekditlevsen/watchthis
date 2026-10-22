// Basket: a swipe basketball game. Pick the ball up at the bottom and flick it up at the basket (top centre); it
// flies with gravity, shrinking as it rises (it travels away), bounces off the rim, the walls and the floor. Coming
// down through the hoop scores a point; a shot that misses ends the streak (the best one is kept until reboot).
// A ball dragged past the middle of the screen is let go of with the finger's speed.
//
// The parts are LVGL objects (the ball moves, so only its old and new boxes are redrawn); 50 frames a second.

private let screenW = Float(WatchScreen.width)
private let screenH = Float(WatchScreen.height)

private let gravity: Float = 1500           // px/s²
private let flickScale: Float = 0.65        // finger speed -> ball speed
private let maxSpeed: Float = 1900
private let wallBounce: Float = 0.6
private let floorBounce: Float = 0.45

private let hoopX: Float = 205
private let rimY: Float = 120
private let rimHalf: Float = 52             // rim ends at hoopX ± rimHalf
private let rimEndRadius: Float = 4
private let rimBounce: Float = 0.3

private let start = (x: Float(205), y: Float(390))
private let nearRadius: Float = 26          // at the start
private let farRadius: Float = 17           // at the rim

private let orange = FaceColor(r: 245, g: 130, b: 40)
private let seam = FaceColor(r: 60, g: 25, b: 5)
private let rimColor = FaceColor(r: 235, g: 80, b: 30)

private var bestStreak = 0

private final class BasketGame {
    enum State {
        case ready, held, flying
    }

    private let screen: LVObj
    private let court: LVObj
    private let net: LVObj
    private let rim: LVObj
    private let ball: LVObj
    private let scoreLabel: LVObj
    private let bestLabel: LVObj
    private var timer: OpaquePointer?

    private var state = State.ready
    private var x = start.x, y = start.y, vx: Float = 0, vy: Float = 0
    private var spin: Float = 0, spinRate: Float = 0
    private var lastTick: UInt32 = 0
    private var flightTime: Float = 0
    private var floorBounces = 0
    // The shot in the air: a real throw (not a drop), above the rim at some point, scored
    private var isShot = false
    private var wasAboveRim = false
    /// Over the hoop's opening (centre above the rim, between its ends): going in from here, by any way (a bounce
    /// off the rim too), scores
    private var overHoop = false
    private var scored = false
    private var ballInFront = true
    private var streak = 0
    private var flashUntil: UInt32 = 0
    // Finger: offset from the ball's centre, and recent positions (for the flick's speed)
    private var grab: (dx: Float, dy: Float) = (0, 0)
    private var samples: [(t: UInt32, x: Float, y: Float)] = []

    init(screen: LVObj) {
        self.screen = screen
        lv_obj_remove_flag(screen, LV_OBJ_FLAG_SCROLLABLE)
        lv_obj_set_style_bg_color(screen, lv_color_make(16, 22, 40), partMain)
        lv_obj_set_style_bg_opa(screen, 255, partMain)

        // The whole screen takes the touches
        court = lvPlainObject(screen)
        lv_obj_set_size(court, Int32(screenW), Int32(screenH))
        lv_obj_add_flag(court, LV_OBJ_FLAG_CLICKABLE)
        lv_obj_remove_flag(court, LV_OBJ_FLAG_GESTURE_BUBBLE)

        scoreLabel = lv_label_create(court)!
        lv_obj_set_style_text_font(scoreLabel, wf_builtin_font(44), partMain)
        lv_obj_set_style_text_color(scoreLabel, lv_color_make(70, 85, 120), partMain)
        lv_obj_align(scoreLabel, LV_ALIGN_CENTER, 0, 0)
        bestLabel = lv_label_create(court)!
        lv_obj_set_style_text_font(bestLabel, wf_builtin_font(16), partMain)
        lv_obj_set_style_text_color(bestLabel, lv_color_make(70, 85, 120), partMain)
        lv_obj_align(bestLabel, LV_ALIGN_CENTER, 0, 38)

        // Backboard, with the square above the rim
        let board = lvPlainObject(court)
        lv_obj_set_pos(board, 130, 24)
        lv_obj_set_size(board, 150, 106)
        lv_obj_set_style_bg_color(board, lv_color_white(), partMain)
        lv_obj_set_style_bg_opa(board, 40, partMain)
        lv_obj_set_style_border_color(board, lv_color_white(), partMain)
        lv_obj_set_style_border_width(board, 3, partMain)
        lv_obj_set_style_radius(board, 4, partMain)
        let square = lvPlainObject(board)
        lv_obj_set_pos(square, 42, 46)
        lv_obj_set_size(square, 60, 44)
        lv_obj_set_style_border_color(square, lv_color_white(), partMain)
        lv_obj_set_style_border_width(square, 3, partMain)

        net = lvPlainObject(court)
        lv_obj_set_pos(net, Int32(hoopX - rimHalf - 4), Int32(rimY))
        lv_obj_set_size(net, Int32(2 * rimHalf + 8), 50)

        ball = lvPlainObject(court)
        lv_obj_set_style_bg_color(ball, lvColor(orange), partMain)
        lv_obj_set_style_bg_opa(ball, 255, partMain)
        lv_obj_set_style_radius(ball, wf_radius_circle(), partMain)

        rim = lvPlainObject(court)
        lv_obj_set_pos(rim, Int32(hoopX - rimHalf - rimEndRadius), Int32(rimY - 3))
        lv_obj_set_size(rim, Int32(2 * (rimHalf + rimEndRadius)), 7)
        lv_obj_set_style_bg_color(rim, lvColor(rimColor), partMain)
        lv_obj_set_style_bg_opa(rim, 255, partMain)
        lv_obj_set_style_radius(rim, 3, partMain)

        let me = Unmanaged.passUnretained(self).toOpaque()
        lv_obj_add_event_cb(net, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            Unmanaged<BasketGame>.fromOpaque(ud).takeUnretainedValue().drawNet(e)
        }, LV_EVENT_DRAW_MAIN, me)
        lv_obj_add_event_cb(ball, { e in
            guard let ud = lv_event_get_user_data(e) else { return }
            Unmanaged<BasketGame>.fromOpaque(ud).takeUnretainedValue().drawSeams(e)
        }, LV_EVENT_DRAW_MAIN, me)
        for code in [LV_EVENT_PRESSED, LV_EVENT_PRESSING, LV_EVENT_RELEASED, LV_EVENT_PRESS_LOST] {
            lv_obj_add_event_cb(court, { e in
                guard let ud = lv_event_get_user_data(e) else { return }
                Unmanaged<BasketGame>.fromOpaque(ud).takeUnretainedValue().touch(e)
            }, code, me)
        }
        timer = lv_timer_create({ t in
            guard let ud = lv_timer_get_user_data(t) else { return }
            Unmanaged<BasketGame>.fromOpaque(ud).takeUnretainedValue().tick()
        }, 20, me)
        lastTick = lv_tick_get()
        updateScore()
        placeBall()
    }

    func stop() {
        if let timer { lv_timer_delete(timer) }
        timer = nil
    }

    // MARK: - Touch

    private func touch(_ e: OpaquePointer?) {
        var p = lv_point_t()
        lv_indev_get_point(lv_indev_active(), &p)
        let fx = Float(p.x), fy = Float(p.y)
        let now = lv_tick_get()
        switch lv_event_get_code(e) {
        case LV_EVENT_PRESSED:
            // On the ball (with some slack), and the ball in the lower half
            let r = radius
            let dx = fx - x, dy = fy - y
            guard y > screenH / 2, dx * dx + dy * dy <= (r + 24) * (r + 24) else { return }
            state = .held
            grab = (dx, dy)
            vx = 0
            vy = 0
            samples = [(now, fx, fy)]
        case LV_EVENT_PRESSING:
            guard state == .held else { return }
            samples.append((now, fx, fy))
            // Keep ~100 ms
            while samples.count > 2, now &- samples[0].t > 100 { samples.removeFirst() }
            x = min(max(fx - grab.dx, radius), screenW - radius)
            y = min(fy - grab.dy, screenH - 10 - radius)
            placeBall()
            if y < screenH / 2 { launch() }
        default: // released, or lost
            guard state == .held else { return }
            samples.append((now, fx, fy))
            launch()
        }
    }

    /// Let go of the ball with the finger's recent speed
    private func launch() {
        var fvx: Float = 0, fvy: Float = 0
        if let first = samples.first, let last = samples.last, last.t &- first.t >= 10 {
            let dt = Float(last.t &- first.t) / 1000
            fvx = (last.x - first.x) / dt * flickScale
            fvy = (last.y - first.y) / dt * flickScale
        }
        let speed = (fvx * fvx + fvy * fvy).squareRoot()
        if speed > maxSpeed {
            fvx *= maxSpeed / speed
            fvy *= maxSpeed / speed
        }
        vx = fvx
        vy = fvy
        spinRate = fvx / 30
        state = .flying
        flightTime = 0
        floorBounces = 0
        isShot = fvy < -400
        wasAboveRim = false
        overHoop = false
        scored = false
        samples.removeAll()
    }

    // MARK: - Physics

    private func tick() {
        let now = lv_tick_get()
        let elapsed = min(Float(now &- lastTick) / 1000, 0.05) // after a slow frame, don't jump
        lastTick = now
        if flashUntil != 0 && Int32(bitPattern: now &- flashUntil) >= 0 {
            flashUntil = 0
            lv_obj_set_style_bg_color(rim, lvColor(rimColor), partMain)
            lv_obj_set_style_text_color(scoreLabel, lv_color_make(70, 85, 120), partMain)
        }
        guard state == .flying else {
            if state == .held { lv_display_trigger_activity(nil) }
            return
        }
        lv_display_trigger_activity(nil)
        // Steps of at most 5 ms, so the ball can't pass through the rim
        let steps = max(1, Int((elapsed / 0.005).rounded(.up)))
        let dt = elapsed / Float(steps)
        for _ in 0..<steps where state == .flying {
            step(dt)
        }
        flightTime += elapsed
        spin += spinRate * elapsed
        if abs(spin) > 2 * FaceMath.pi { spin -= (spin / (2 * FaceMath.pi)).rounded(.towardZero) * 2 * FaceMath.pi }
        if state == .flying && (floorBounces >= 3 || flightTime > 6) {
            endShot()
        }
        // Rising, the ball is in front of the hoop; falling, behind the rim's front
        let inFront = vy < 0 || y > rimY + 40
        if inFront != ballInFront {
            ballInFront = inFront
            if inFront {
                lv_obj_move_foreground(ball)
            } else {
                lv_obj_move_foreground(net)
                lv_obj_move_foreground(rim)
            }
        }
        placeBall()
    }

    private func step(_ dt: Float) {
        vy += gravity * dt
        x += vx * dt
        y += vy * dt
        let r = radius
        if y < rimY - r { wasAboveRim = true }
        // Walls, ceiling, floor
        if x < r {
            x = r
            vx = -vx * wallBounce
        } else if x > screenW - r {
            x = screenW - r
            vx = -vx * wallBounce
        }
        if y < r {
            y = r
            vy = -vy * wallBounce
        }
        let floor = screenH - 10 - r
        if y > floor {
            y = floor
            if vy > 120 {
                vy = -vy * floorBounce
                floorBounces += 1
            } else {
                vy = 0
                floorBounces = 3
            }
            vx *= 0.8
            spinRate = vx / 30
        }
        // Through the hoop is a point: from over the opening to well under the rim, still inside it
        let insideRim = abs(x - hoopX) < rimHalf - rimEndRadius
        if y < rimY && insideRim && wasAboveRim {
            overHoop = true
        } else if y > rimY + 60 {
            overHoop = false
        }
        if !scored && isShot && overHoop && y > rimY + 0.6 * r && insideRim {
            score()
        }
        // Coming down, the rim's ends are in the way
        guard vy > 0 else { return }
        for endX in [hoopX - rimHalf, hoopX + rimHalf] {
            let dx = x - endX, dy = y - rimY
            let d2 = dx * dx + dy * dy
            let reach = r + rimEndRadius
            if d2 < reach * reach && d2 > 0.01 {
                let d = d2.squareRoot()
                let nx = dx / d, ny = dy / d
                x = endX + nx * reach
                y = rimY + ny * reach
                let vn = vx * nx + vy * ny
                if vn < 0 {
                    vx -= (1 + rimBounce) * vn * nx
                    vy -= (1 + rimBounce) * vn * ny
                    spinRate = vx / 30
                }
            }
        }
    }

    private func score() {
        scored = true
        streak += 1
        bestStreak = max(bestStreak, streak)
        vx *= 0.3 // the net catches it
        updateScore()
        flashUntil = lv_tick_get() &+ 400
        lv_obj_set_style_bg_color(rim, lv_color_make(255, 210, 60), partMain)
        lv_obj_set_style_text_color(scoreLabel, lvColor(orange), partMain)
    }

    /// The ball has landed: a missed shot ends the streak; a new ball at the start
    private func endShot() {
        if isShot && !scored && streak > 0 {
            streak = 0
            updateScore()
        }
        state = .ready
        x = start.x
        y = start.y
        vx = 0
        vy = 0
        spinRate = 0
        if !ballInFront {
            ballInFront = true
            lv_obj_move_foreground(ball)
        }
    }

    /// Smaller the higher it is (further away)
    private var radius: Float {
        let k = min(max((start.y - y) / (start.y - rimY), 0), 1)
        return nearRadius - (nearRadius - farRadius) * k
    }

    private func placeBall() {
        let r = radius.rounded()
        lv_obj_set_pos(ball, Int32((x - r).rounded()), Int32((y - r).rounded()))
        lv_obj_set_size(ball, Int32(2 * r), Int32(2 * r))
    }

    private func updateScore() {
        lvSetText(scoreLabel, "\(streak)")
        lvSetText(bestLabel, bestStreak > 0 ? "Bedste: \(bestStreak)" : "Kast bolden op i kurven")
    }

    // MARK: - Drawing

    private func line(_ layer: UnsafeMutablePointer<lv_layer_t>, _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float,
                      width: Int32, _ color: FaceColor) {
        var dsc = lv_draw_line_dsc_t()
        lv_draw_line_dsc_init(&dsc)
        dsc.p1 = wf_point(Int32(x1.rounded()), Int32(y1.rounded()))
        dsc.p2 = wf_point(Int32(x2.rounded()), Int32(y2.rounded()))
        dsc.width = width
        dsc.color = lvColor(color)
        dsc.opa = color.a
        dsc.round_start = 1
        dsc.round_end = 1
        lv_draw_line(layer, &dsc)
    }

    /// The ball's seams, turned by its spin: two lines across, and a curve on each side
    private func drawSeams(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        var area = lv_area_t()
        lv_obj_get_coords(ball, &area)
        let r = Float(area.x2 - area.x1 + 1) / 2
        let cx = Float(area.x1) + r, cy = Float(area.y1) + r
        let c = FaceMath.cos(spin), s = FaceMath.sin(spin)
        let w: Int32 = r > 22 ? 3 : 2
        line(layer, cx - c * r, cy - s * r, cx + c * r, cy + s * r, width: w, seam)
        line(layer, cx + s * r, cy - c * r, cx - s * r, cy + c * r, width: w, seam)
        for side: Float in [-1, 1] {
            var dsc = lv_draw_arc_dsc_t()
            lv_draw_arc_dsc_init(&dsc)
            dsc.color = lvColor(seam)
            dsc.width = w
            // A circle outside the ball whose edge curves through it
            let d = 1.35 * r
            dsc.center = lv_point_t(x: Int32((cx + side * c * d).rounded()), y: Int32((cy + side * s * d).rounded()))
            dsc.radius = UInt16(max(2, (0.95 * r).rounded()))
            let facing = spin * 180 / FaceMath.pi + (side < 0 ? 0 : 180)
            let a = Int32(facing.rounded()) % 360
            dsc.start_angle = ((a - 42) % 360 + 360) % 360
            dsc.end_angle = ((a + 42) % 360 + 360) % 360
            lv_draw_arc(layer, &dsc)
        }
    }

    /// The net: from the rim, narrowing downwards, with crossing strings
    private func drawNet(_ e: OpaquePointer?) {
        guard let layer = lv_event_get_layer(e) else { return }
        let netColor = FaceColor(r: 230, g: 230, b: 235, a: 200)
        let top: Float = rimY + 3, bottom: Float = rimY + 46
        let n = 6
        func at(_ i: Int, _ row: Float) -> (Float, Float) {
            // Position i (0...n) across the net at height row (0 = rim, 1 = bottom)
            let half = rimHalf - (rimHalf - 28) * row
            return (hoopX - half + 2 * half * Float(i) / Float(n), top + (bottom - top) * row)
        }
        for i in 0..<n {
            let a = at(i, 0), b = at(i + 1, 1)
            line(layer, a.0, a.1, b.0, b.1, width: 2, netColor)
            let c = at(i + 1, 0), d = at(i, 1)
            line(layer, c.0, c.1, d.0, d.1, width: 2, netColor)
        }
        let a = at(0, 1), b = at(n, 1)
        line(layer, a.0, a.1, b.0, b.1, width: 2, netColor)
    }
}

nonisolated(unsafe) private var basketGame: BasketGame?

@_cdecl("basket_app_show")
public func basket_app_show(_ screen: OpaquePointer?) {
    guard let screen else { return }
    basketGame = BasketGame(screen: screen)
}

@_cdecl("basket_app_hide")
public func basket_app_hide() {
    // The timer goes now; the objects are deleted by the app framework after this, and their draw callbacks point
    // at the game, so it is kept until the next show
    basketGame?.stop()
}
