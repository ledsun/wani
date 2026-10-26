require_relative "test_helper"
require "wani/browser/bridge_progress"

class BridgeProgressTest < Minitest::Test
  def state(number, total)
    Wani::Browser::BridgeProgress.new(number, total)
  end

  def test_bridge_builds_before_rabbit_crosses
    assert_equal [0, 10, 20, 20, 20], (0..4).map { |number| state(number, 4).sharks }
    assert_equal [0, 0, 0, 0.5, 1.0], (0..4).map { |number| state(number, 4).rabbit_fraction }
  end

  def test_odd_slide_count_and_single_slide_finish_at_right_edge
    assert_equal 16, state(2, 5).sharks
    assert_equal 0, state(2, 5).rabbit_fraction
    assert_equal 20, state(3, 5).sharks
    assert_in_delta 0.2, state(3, 5).rabbit_fraction
    assert_equal 1.0, state(5, 5).rabbit_fraction
    assert_equal 20, state(1, 1).sharks
    assert_equal 1.0, state(1, 1).rabbit_fraction
  end

  def test_out_of_range_indices_are_clamped
    assert_equal 0, state(-1, 4).sharks
    assert_equal 1.0, state(99, 4).rabbit_fraction
    assert_raises(ArgumentError) { state(1, 0) }
  end
end
