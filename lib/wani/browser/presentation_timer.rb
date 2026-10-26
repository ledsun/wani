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
        tick_timer
      end

      def tick_timer
        remaining = ((@deadline - JS.global[:Date].now.to_f) / 1000).ceil
        countdown = element("countdown")
        countdown[:hidden] = remaining > 30 || remaining <= 0
        countdown[:textContent] = "残り #{remaining} 秒" if remaining.between?(1, 30)
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
