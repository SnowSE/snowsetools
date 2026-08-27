defmodule SnowSeTools.SyllabusScrubberTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.SyllabusScrubber

  test "keeps http/https/mailto links and classes" do
    html = ~s(<div class="fr-view"><a class="x" href="https://snow.edu">Snow</a></div>)
    assert SyllabusScrubber.sanitize(html) == html
    assert SyllabusScrubber.sanitize(~s(<a href="mailto:a@b.c">m</a>)) =~ ~s(href="mailto:a@b.c")
  end

  test "drops javascript: and data: hrefs" do
    refute SyllabusScrubber.sanitize("<a href=\"javascript:alert(1)\">x</a>") =~ "javascript"
    refute SyllabusScrubber.sanitize("<a href=\"JaVaScRiPt:alert(1)\">x</a>") =~ "alert"
    refute SyllabusScrubber.sanitize(~s(<a href="data:text/html,hi">x</a>)) =~ "data:"
  end

  test "strips scripts, event handlers, styles and ids" do
    out =
      SyllabusScrubber.sanitize(
        "<p id=\"p\" onclick=\"x()\" style=\"a:b\"><script>1</script>t</p>"
      )

    refute out =~ "<script"
    refute out =~ "onclick"
    refute out =~ "style"
    refute out =~ "id="
    assert out =~ "t</p>"
  end
end
