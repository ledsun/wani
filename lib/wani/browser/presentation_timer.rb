module Wani
  module Browser
    class Application
      private

      def start_timer
        return if @presentation.time_limit.zero?

        @deadline = JS.global[:Date].now.to_f + @presentation.time_limit * 60_000
        element("resume-slides").addEventListener("click") { go(@index) }
        @timer_callback = -> { tick_timer }
        @timer_id = JS.global.setInterval(@timer_callback, 200)
        # Check immediately when returning from a background tab, whose timers may be throttled.
        @document.addEventListener("visibilitychange") { tick_timer unless @timer_finished }
        update_timer_for_slide
      end

      def update_timer_for_slide
        return unless @deadline && !@timer_finished

        now = JS.global[:Date].now.to_f
        if @index == @sections.length - 1
          @timer_paused_at ||= now
          element("countdown")[:hidden] = true
        else
          if @timer_paused_at
            @deadline += now - @timer_paused_at
            @timer_paused_at = nil
          end
          tick_timer
        end
      end

      def tick_timer
        return if @timer_paused_at || @timer_finished

        remaining = ((@deadline - JS.global[:Date].now.to_f) / 1000).ceil
        countdown = element("countdown")
        countdown[:hidden] = remaining > 30 || remaining <= 0
        if remaining.between?(1, 30) && remaining != @last_countdown
          @last_countdown = remaining
          urgent = remaining <= 5
          countdown[:classList].toggle("urgent", urgent)
          countdown.setAttribute("aria-label", "発表の残り時間 #{remaining} 秒")
          if urgent
            number = @document.createElement("span")
            number[:textContent] = remaining.to_s
            number[:style].setProperty("--countdown-peak", "#{(6 - remaining) * 20}vmin")
            countdown.replaceChildren(number)
          else
            countdown[:textContent] = "残り #{remaining} 秒"
          end
        end
        return if remaining > 0

        JS.global.clearInterval(@timer_id)
        @timer_finished = true
        @time_expired = true
        element("time-expired")[:hidden] = false
        element("viewport")[:inert] = true
        element("resume-slides").focus
        update_buttons
      end
    end
  end
end
