module Wani
  module Browser
    # Page progress builds a bridge in the first half and crosses it in the second.
    class BridgeProgress
      SEGMENTS = 20
      attr_reader :sharks, :rabbit_fraction

      def initialize(number, total)
        raise ArgumentError, "Slide count must be positive" unless total.positive?
        number = number.clamp(0, total)
        @sharks = [(SEGMENTS * 2 * number + total - 1) / total, SEGMENTS].min
        @rabbit_fraction = (2.0 * number / total - 1).clamp(0, 1)
      end
    end
  end
end
