module Wani
  module Browser
    # Page progress builds a bridge in the first half and crosses it in the second.
    class BridgeProgress
      SEGMENTS = 20
      attr_reader :sharks, :rabbit_fraction

      def initialize(number, total)
        raise ArgumentError, "Slide count must be positive" unless total.positive?
        number = number.clamp(0, total)
        # Anchor the first page at one wani, reaching the full bridge halfway.
        # A two-page deck completes the bridge on page two; a single page stays at one.
        steps = [(total + 1) / 2, 2].max - 1
        @sharks = number.zero? ? 0 : [1 + ((SEGMENTS - 1) * (number - 1) + steps - 1) / steps, SEGMENTS].min
        @rabbit_fraction = (2.0 * number / total - 1).clamp(0, 1)
      end
    end
  end
end
