require_relative "test_helper"
require "wani/core/parser"

class YoutubeTest < Minitest::Test
  def test_video_url_is_rendered_with_validated_range
    slide = Wani::Core::Parser.new.parse("# Video\n\n![Example](https://www.youtube.com/watch?v=M7lc1UVf-VE&start=90&end=150)").slides.first
    assert_includes slide.html, 'data-youtube-src="https://www.youtube.com/embed/M7lc1UVf-VE?start=90&amp;end=150"'
    assert_includes slide.html, 'https://i.ytimg.com/vi/M7lc1UVf-VE/hqdefault.jpg'
    assert_includes slide.html, 'aria-label="Exampleを再生"'
  end

  def test_invalid_urls_are_never_interpreted_as_videos
    %w[https://www.youtube.com.evil.test/watch?v=M7lc1UVf-VE https://www.youtube.com/watch?v=M7lc1UVf-VE&start=150&end=90 https://www.youtube.com/watch?v=M7lc1UVf-VE&start=1&start=2 https://www.youtube.com/watch?v=M7lc1UVf-VE&end=1%22].each do |url|
      assert_nil Wani::Core::SafeHTML.youtube(url)
    end
  end
end
