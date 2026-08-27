defmodule SnowSeTools.SyllabusScrubber do
  @moduledoc """
  HTML scrubber for syllabus content from the SimpleSyllabus API.

  Extends basic_html (no inline styles) and adds `class` and `div` so that
  our .fr-view / .component-name CSS selectors still work. Angular component
  tags are stripped automatically since they are not in the allowlist.
  """
  use HtmlSanitizeEx, extend: :basic_html

  # Allow div and span with class so .fr-view / .component-name selectors work
  allow_tag_with_these_attributes("div", ["class"])
  allow_tag_with_these_attributes("span", ["class"])
  allow_tag_with_these_attributes("p", ["class"])
  allow_tag_with_these_attributes("h1", ["class"])
  allow_tag_with_these_attributes("h2", ["class"])
  allow_tag_with_these_attributes("h3", ["class"])
  allow_tag_with_these_attributes("ul", ["class"])
  allow_tag_with_these_attributes("ol", ["class"])
  allow_tag_with_these_attributes("li", ["class"])
  # `href` must go through the URI allowlist: a plain `allow_tag_with_these_attributes`
  # clause would shadow BasicHTML's scheme check and let `javascript:` links through.
  allow_tag_with_uri_attributes("a", ["href"], ["http", "https", "mailto"])
  allow_tag_with_these_attributes("a", ["class"])
  allow_tag_with_these_attributes("strong", ["class"])
  allow_tag_with_these_attributes("em", ["class"])
  allow_tag_with_these_attributes("b", ["class"])
end
